defmodule Jexata.Evaluator do
  @moduledoc false
  alias Jexata.{Error, Functions, Semantics}
  alias Jexata.Runtime.{Builtin, Closure, Composition, Partial, Signature, Transform, Value}
  alias Jexata.Runtime.Partial.Placeholder

  @spec evaluate(Jexata.AST.t(), term()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(ast, data), do: evaluate(ast, data, %{})

  @spec evaluate(Jexata.AST.t(), term(), map()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(ast, data, environment, max_function_depth)
      when is_integer(max_function_depth) and max_function_depth > 0 do
    key = {__MODULE__, :max_function_depth}
    prior = Process.get(key)
    Process.put(key, max_function_depth)

    try do
      evaluate(ast, data, environment)
    after
      if prior == nil, do: Process.delete(key), else: Process.put(key, prior)
    end
  end

  def evaluate(ast, :undefined, environment) do
    missing = Value.undefined()
    eval(ast, missing, %{root: missing, environment: environment})
  end

  def evaluate(ast, data, environment),
    do: eval(ast, data, %{root: data, environment: environment})

  defp eval({:literal, value}, _, _), do: {:ok, value}
  defp eval(:placeholder, _, _), do: {:ok, %Placeholder{}}

  defp eval({:transform, pattern, update, delete}, _, context),
    do:
      {:ok,
       %Transform{
         pattern: pattern,
         update: update,
         delete: delete,
         environment: context.environment
       }}

  defp eval({:name, name}, data, _), do: {:ok, Semantics.select(data, name)}
  defp eval({:variable, "$"}, data, _), do: {:ok, data}
  defp eval({:variable, "$$"}, _, %{root: root}), do: {:ok, root}

  defp eval({:variable, name}, _, %{environment: environment}) do
    case Map.fetch(environment, name) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        if Functions.supported?(name),
          do: {:ok, %Builtin{name: name}},
          else: {:ok, Value.undefined()}
    end
  end

  defp eval(:wildcard, data, _root) when is_map(data),
    do: {:ok, Value.sequence(Enum.flat_map(Map.values(data), &Value.items/1))}

  defp eval(:wildcard, data, _root), do: {:ok, Value.sequence(Value.items(data))}
  defp eval(:descendants, data, _context), do: {:ok, Value.sequence(descendants(data))}

  defp eval({:path, {:variable, "$"} = left, {:object, pairs}}, data, context),
    do: eval({:group, left, pairs}, data, context)

  defp eval({:compiled_path, _left, _right, true} = path, data, context) do
    with {:ok, frames} <- eval_indexed(path, data, context),
         do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)))}
  end

  defp eval({:compiled_path, left, right, false}, data, context),
    do: eval_path_steps(left, right, data, context)

  defp eval({:path, left, _} = path, data, context) do
    if indexed_path?(left) do
      with {:ok, frames} <- eval_indexed(path, data, context),
           do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)))}
    else
      eval_regular_path(path, data, context)
    end
  end

  defp eval({:index_bind, _, _} = path, data, context) do
    with {:ok, frames} <- eval_indexed(path, data, context),
         do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)))}
  end

  defp eval({:group, left, pairs}, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, result} ->
        case group_items(Value.items(source), key_ast, context) do
          {:ok, groups} ->
            Enum.reduce_while(groups, {:ok, result}, fn {key, items}, {:ok, acc} ->
              case eval(value_ast, Enum.reverse(items), context) do
                {:ok, value} ->
                  cond do
                    Value.undefined?(value) ->
                      {:cont, {:ok, acc}}

                    Map.has_key?(acc, key) ->
                      {:halt, {:error, Error.new("D1009", "Duplicate object key")}}

                    true ->
                      {:cont, {:ok, Map.put(acc, key, value)}}
                  end

                error ->
                  {:halt, error}
              end
            end)
            |> case do
              {:ok, value} -> {:cont, {:ok, value}}
              error -> {:halt, error}
            end

          error ->
            {:halt, error}
        end
      end)
    end
  end

  defp eval({:sort, left, terms}, data, context) do
    if indexed_path?(left) do
      with {:ok, frames} <- eval_indexed({:sort, left, terms}, data, context),
           do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)))}
    else
      eval_regular_sort(left, terms, data, context)
    end
  end

  defp eval({:keep_array, ast}, data, context) do
    with {:ok, value} <- eval(ast, data, context),
         do: {:ok, Value.sequence(Value.items(value), true)}
  end

  defp eval({:filter, left, predicate}, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      items = Value.items(source)
      count = if boolean_predicate?(predicate), do: 0, else: length(items)

      items
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
        case eval(predicate, item, root) do
          {:ok, result} ->
            keep = predicate_matches?(result, index, count)
            {:cont, {:ok, if(keep, do: [item | acc], else: acc)}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, values} ->
          {:ok,
           Value.sequence(
             Enum.reverse(values),
             is_struct(source, Value.Sequence) and source.keep_array
           )}

        error ->
          error
      end
    end
  end

  defp eval({:array, expressions}, data, root) do
    with {:ok, values} <- eval_list(expressions, data, root) do
      {:ok,
       expressions
       |> Enum.zip(values)
       |> Enum.flat_map(fn
         {{:array, _}, value} -> [value]
         {_, %Value.Sequence{items: items}} -> items
         {_, value} when is_list(value) -> value
         {_, value} -> if Value.undefined?(value), do: [], else: [value]
       end)}
    end
  end

  defp eval({:object, pairs}, data, root) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, acc} ->
      with {:ok, key} <- eval(key_ast, data, root),
           {:ok, value} <- eval(value_ast, data, root),
           true <- is_binary(key) do
        {:cont, {:ok, if(Value.undefined?(value), do: acc, else: Map.put(acc, key, value))}}
      else
        false -> {:halt, {:error, Error.new("T1003", "Object key must be a string")}}
        error -> {:halt, error}
      end
    end)
  end

  defp eval({:negate, ast}, data, root) do
    with {:ok, value} <- eval(ast, data, root) do
      cond do
        Value.undefined?(value) -> {:ok, value}
        is_number(value) -> {:ok, -value}
        true -> {:error, Error.new("D1002", "Unary minus requires a number")}
      end
    end
  end

  defp eval(
         {:binary, "~>",
          {:array, [{:binary, "..", {:literal, start}, {:literal, finish}}]} = left,
          {:call, {:variable, "$count"}, []}},
         data,
         context
       )
       when is_integer(start) and is_integer(finish) and finish - start + 1 > 100_000 do
    if Map.has_key?(context.environment, "$count") do
      with {:ok, value} <- eval(left, data, context),
           do: invoke(context.environment["$count"], [value], data)
    else
      if finish - start + 1 > 10_000_000,
        do: {:error, Error.new("D2014", "Range exceeds the configured limit")},
        else: {:ok, finish - start + 1}
    end
  end

  defp eval({:binary, "~>", left, {:keep_array, {:call, _, _} = call}}, data, context) do
    with {:ok, value} <- eval({:binary, "~>", left, call}, data, context),
         do: {:ok, Value.sequence(Value.items(value), true)}
  end

  defp eval({:binary, "~>", left, {:call, {:variable, name}, args}}, data, context) do
    with {:ok, value} <- eval(left, data, context),
         {:ok, values} <- eval_list(args, data, context) do
      target =
        case Map.fetch(context.environment, name) do
          {:ok, function} ->
            with_recursive_bindings(function, context.environment)

          :error ->
            if Functions.supported?(name), do: %Builtin{name: name}, else: Value.undefined()
        end

      if callable?(value) and callable?(target) do
        arguments =
          if Enum.any?(values, &is_struct(&1, Placeholder)),
            do: values,
            else: [%Placeholder{} | values]

        {:ok,
         %Composition{first: value, second: %Partial{function: target, arguments: arguments}}}
      else
        case target do
          %Builtin{name: name}
          when name in ["$map", "$filter", "$reduce", "$single", "$each", "$sift", "$sort"] ->
            higher_order(name, [value | values], data)

          _ ->
            invoke(target, [value | values], data)
        end
      end
    end
  end

  defp eval({:binary, "~>", left, target}, data, context) do
    with {:ok, value} <- eval(left, data, context),
         {:ok, function} <- eval(target, data, context) do
      cond do
        callable?(value) and callable?(function) ->
          {:ok, %Composition{first: value, second: function}}

        callable?(function) ->
          invoke(function, [value], data)

        true ->
          {:error, Error.new("T2006", "Right side of ~> must be a function")}
      end
    end
  end

  defp eval({:binary, "?:", left, right}, data, context) do
    with {:ok, value} <- eval(left, data, context) do
      if Semantics.boolean(value), do: {:ok, value}, else: eval(right, data, context)
    end
  end

  defp eval({:binary, "??", left, right}, data, context) do
    with {:ok, value} <- eval(left, data, context) do
      if Value.undefined?(value), do: eval(right, data, context), else: {:ok, value}
    end
  end

  defp eval({:binary, "and", left, right}, data, root) do
    with {:ok, value} <- eval(left, data, root) do
      if Semantics.boolean(value), do: eval_boolean(right, data, root), else: {:ok, false}
    end
  end

  defp eval({:binary, "or", left, right}, data, root) do
    with {:ok, value} <- eval(left, data, root) do
      if Semantics.boolean(value), do: {:ok, true}, else: eval_boolean(right, data, root)
    end
  end

  defp eval({:binary, ":=", {:variable, name}, right}, data, context)
       when name not in ["$", "$$"], do: eval(right, data, context)

  defp eval({:binary, ":=", _, _}, _, _),
    do: {:error, Error.new("S0212", "Binding target must be a variable")}

  defp eval({:lambda, parameters, signature, body}, data, context) do
    {:ok,
     %Closure{
       parameters: parameters,
       arity: length(parameters),
       body: body,
       environment: context.environment,
       root: context.root,
       context_value: data,
       signature: Signature.prepare(signature, length(parameters)),
       references:
         body |> referenced_variables() |> expand_closure_references(context.environment)
     }}
  end

  defp eval({:compiled_lambda, parameters, signature, body, references}, data, context) do
    {:ok,
     %Closure{
       parameters: parameters,
       arity: length(parameters),
       body: body,
       environment: context.environment,
       root: context.root,
       context_value: data,
       signature: signature,
       references: expand_closure_references(MapSet.new(references), context.environment)
     }}
  end

  defp eval({:binary, op, left, right}, data, root) do
    with {:ok, a} <- eval(left, data, root),
         {:ok, b} <- eval(right, data, root) do
      binary(op, a, b)
    end
  end

  defp eval({:conditional, test, yes, no}, data, root) do
    with {:ok, value} <- eval(test, data, root) do
      eval(if(Semantics.boolean(value), do: yes, else: no), data, root)
    end
  end

  defp eval({:call, {:variable, name}, args}, data, context)
       when name in ["$map", "$filter", "$reduce", "$single", "$each", "$sift", "$sort"] do
    with {:ok, values} <- eval_list(args, data, context) do
      if Enum.any?(values, &is_struct(&1, Placeholder)) do
        {:ok, %Partial{function: %Builtin{name: name}, arguments: values}}
      else
        values =
          if name in ["$each", "$sift"] and length(values) == 1, do: [data | values], else: values

        higher_order(name, values, data)
      end
    end
  end

  defp eval({:call, {:variable, "$eval"}, args}, data, context) do
    with {:ok, values} <- eval_list(args, data, context) do
      case values do
        [source] when is_binary(source) -> evaluate_source(source, data, context)
        [source, input] when is_binary(source) -> evaluate_source(source, input, context)
        [source] when is_struct(source, Value.Undefined) -> {:ok, Value.undefined()}
        _ -> {:error, Error.new("T0410", "Invalid arguments for $eval")}
      end
    end
  end

  defp eval({:call, {:variable, "$replace"}, args}, data, context) do
    with {:ok, values} <- eval_list(args, data, context) do
      case Map.fetch(context.environment, "$replace") do
        {:ok, closure} ->
          invoke(with_recursive_bindings(closure, context.environment), values, data)

        :error ->
          case values do
            [value, %Regex{} = pattern, %Closure{} = callback] when is_binary(value) ->
              replace_callback(value, pattern, callback, :all, data)

            [value, %Regex{} = pattern, %Closure{} = callback, limit]
            when is_binary(value) and is_integer(limit) and limit >= 0 ->
              replace_callback(value, pattern, callback, limit, data)

            _ ->
              Functions.call("$replace", values, data)
          end
      end
    end
  end

  defp eval({:call, {:variable, "$string"}, [{:object, _} = object | rest]} = ast, data, context)
       when length(rest) <= 1 do
    if Map.has_key?(context.environment, "$string") do
      eval_string_call(ast, data, context)
    else
      with {:ok, pretty} <- string_pretty_option(rest, data, context),
           {:ok, ordered} <- eval_ordered_value(object, data, context) do
        {:ok, Jexata.Functions.String.stringify_ordered(ordered, pretty)}
      end
    end
  end

  defp eval({:call, {:variable, "$string"}, args} = ast, data, context) do
    if Map.has_key?(context.environment, "$string") do
      eval_string_call(ast, data, context)
    else
      case eval_list(args, data, context) do
        {:ok, values} ->
          if Enum.any?(values, &is_struct(&1, Placeholder)) do
            {:ok, %Partial{function: %Builtin{name: "$string"}, arguments: values}}
          else
            Functions.call("$string", values, data)
          end

        {:error, %Error{code: "D1001"}} ->
          {:error, Error.new("D3001", "Non-finite number")}

        error ->
          error
      end
    end
  end

  defp eval({:call, {:variable, "$match"}, args}, data, context) do
    with {:ok, values} <- eval_list(args, data, context) do
      case Map.fetch(context.environment, "$match") do
        {:ok, function} ->
          invoke(with_recursive_bindings(function, context.environment), values, data)

        :error ->
          if Enum.any?(values, &is_struct(&1, Placeholder)) do
            {:ok, %Partial{function: %Builtin{name: "$match"}, arguments: values}}
          else
            case values do
              [value, %Closure{} = matcher] when is_binary(value) ->
                match_callback(matcher, value)

              _ ->
                Functions.call("$match", values, data)
            end
          end
      end
    end
  end

  defp eval({:call, {:variable, "$split"}, args}, data, context) do
    with {:ok, values} <- eval_list(args, data, context) do
      case values do
        [value, matcher] when is_binary(value) and is_struct(matcher, Builtin) ->
          {:error, Error.new("T1010", "$split matcher did not return a match object")}

        _ ->
          Functions.call("$split", values, data)
      end
    end
  end

  defp eval({:call, {:variable, name}, args}, data, context) do
    with {:ok, values} <- eval_list(args, data, context) do
      case Map.fetch(context.environment, name) do
        {:ok, closure} ->
          invoke_or_partial(with_recursive_bindings(closure, context.environment), values, data)

        :error ->
          if Enum.any?(values, &is_struct(&1, Placeholder)) do
            if Functions.supported?(name),
              do: {:ok, %Partial{function: %Builtin{name: name}, arguments: values}},
              else: {:error, Error.new("T1008", "Unknown function #{name}")}
          else
            Functions.call(name, values, data)
          end
      end
    end
  end

  defp eval({:call, target, args}, data, context) do
    with {:ok, function} <- eval(target, data, context),
         {:ok, values} <- eval_list(args, data, context) do
      if Enum.any?(values, &is_struct(&1, Placeholder)) and Value.undefined?(function) do
        code =
          case target do
            {:name, name} -> if Functions.supported?("$" <> name), do: "T1007", else: "T1008"
            _ -> "T1007"
          end

        {:error, Error.new(code, "Partial application requires a function")}
      else
        if Enum.any?(values, &is_struct(&1, Placeholder)) and not callable?(function) do
          {:error, Error.new("T1008", "Partial application requires a function")}
        else
          if Value.undefined?(function) and match?({:name, _}, target),
            do:
              {:error,
               Error.new(
                 if(Functions.supported?("$" <> elem(target, 1)), do: "T1005", else: "T1006"),
                 "Unknown function"
               )},
            else:
              invoke_or_partial(
                with_recursive_bindings(function, context.environment),
                values,
                data
              )
        end
      end
    end
  end

  defp eval({:block, nodes}, data, context) do
    Enum.reduce_while(nodes, {:ok, Value.undefined(), context}, fn
      {:binary, ":=", _, _} = binding, {:ok, _, current} ->
        case eval_binding(binding, data, current) do
          {:ok, value, next} -> {:cont, {:ok, value, next}}
          error -> {:halt, error}
        end

      node, {:ok, _, current} ->
        case eval(node, data, current) do
          {:ok, value} -> {:cont, {:ok, value, current}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, value, _} -> {:ok, value}
      error -> error
    end
  end

  defp eval_regular_path({:path, {:filter, left, predicate}, {:name, name}}, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      items = Value.items(source)
      count = if boolean_predicate?(predicate), do: 0, else: length(items)
      keep_array? = is_struct(source, Value.Sequence) and source.keep_array

      Enum.reduce_while(items, {:ok, [], 0, 0}, fn item, {:ok, selected, index, kept} ->
        case eval(predicate, item, context) do
          {:ok, result} ->
            if predicate_matches?(result, index, count) do
              {:cont, {:ok, [Semantics.select(item, name) | selected], index + 1, kept + 1}}
            else
              {:cont, {:ok, selected, index + 1, kept}}
            end

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, selected, _, kept} ->
          selected = Enum.reverse(selected)

          values =
            if kept > 1 or keep_array?,
              do: Enum.flat_map(selected, &Value.items/1),
              else: selected

          {:ok, Value.sequence(values, keep_array?)}

        error ->
          error
      end
    end
  end

  defp eval_regular_path({:path, left, right}, data, root) do
    left =
      if match?({:literal, name} when is_binary(name), left),
        do: {:name, elem(left, 1)},
        else: left

    right =
      if match?({:literal, name} when is_binary(name), right),
        do: {:name, elem(right, 1)},
        else: right

    right = contextual_path_call(right)

    eval_path_steps(left, right, data, root)
  end

  defp eval_path_steps(left, right, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      source
      |> Value.items()
      |> eval_each(
        right,
        root,
        is_list(source) or is_struct(source, Value.Sequence),
        (is_struct(source, Value.Sequence) and source.keep_array) or
          match?({:keep_array, _}, right)
      )
    end
  end

  defp eval_regular_sort(left, terms, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      source
      |> Value.items()
      |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
        case eval_sort_keys(terms, item, context) do
          {:ok, keys} -> {:cont, {:ok, [{item, keys} | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, decorated} ->
          decorated = Enum.reverse(decorated)

          case validate_sort_keys(decorated) do
            :ok ->
              sorted = Enum.sort(decorated, fn {_, a}, {_, b} -> compare_sort_keys(a, b) end)
              {:ok, Value.sequence(Enum.map(sorted, &elem(&1, 0)))}

            error ->
              error
          end

        error ->
          error
      end
    end
  end

  defp indexed_path?({:index_bind, _, _}), do: true
  defp indexed_path?({:compiled_path, _, _, indexed?}), do: indexed?
  defp indexed_path?({:path, left, _}), do: indexed_path?(left)
  defp indexed_path?({:sort, left, _}), do: indexed_path?(left)
  defp indexed_path?({:filter, left, _}), do: indexed_path?(left)
  defp indexed_path?(_), do: false

  defp eval_indexed({:index_bind, left, name}, data, context) do
    with {:ok, frames} <- eval_indexed(left, data, context) do
      {:ok,
       frames
       |> Enum.flat_map(fn {value, environment} ->
         value
         |> Value.items()
         |> Enum.map(&{&1, environment})
       end)
       |> Enum.with_index()
       |> Enum.map(fn {{item, environment}, index} ->
         {item, Map.put(environment, name, index)}
       end)}
    end
  end

  defp eval_indexed({:path, left, right}, data, context) do
    right =
      if match?({:literal, name} when is_binary(name), right),
        do: {:name, elem(right, 1)},
        else: contextual_path_call(right)

    eval_indexed_path(left, right, data, context)
  end

  defp eval_indexed({:compiled_path, left, right, _}, data, context),
    do: eval_indexed_path(left, right, data, context)

  defp eval_indexed({:sort, left, terms}, data, context) do
    with {:ok, frames} <- eval_indexed(left, data, context) do
      Enum.reduce_while(frames, {:ok, []}, fn {item, environment} = frame, {:ok, acc} ->
        case eval_sort_keys(terms, item, %{context | environment: environment}) do
          {:ok, keys} -> {:cont, {:ok, [{frame, keys} | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, decorated} ->
          decorated = Enum.reverse(decorated)

          with :ok <- validate_sort_keys(decorated) do
            {:ok,
             decorated
             |> Enum.sort(fn {_, a}, {_, b} -> compare_sort_keys(a, b) end)
             |> Enum.map(&elem(&1, 0))}
          end

        error ->
          error
      end
    end
  end

  defp eval_indexed(ast, data, context) do
    with {:ok, value} <- eval(ast, data, context),
         do: {:ok, [{value, context.environment}]}
  end

  defp eval_indexed_path(left, right, data, context) do
    with {:ok, frames} <- eval_indexed(left, data, context) do
      Enum.reduce_while(frames, {:ok, []}, fn {item, environment}, {:ok, acc} ->
        case eval(right, item, %{context | environment: environment}) do
          {:ok, value} ->
            next = Enum.map(Value.items(value), &{&1, environment})
            {:cont, {:ok, [next | acc]}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, values |> Enum.reverse() |> List.flatten()}
        error -> error
      end
    end
  end

  defp eval_string_call({:call, _, args}, data, context) do
    with {:ok, values} <- eval_list(args, data, context),
         do: invoke(context.environment["$string"], values, data)
  end

  defp string_pretty_option([], _data, _context), do: {:ok, false}

  defp string_pretty_option([option], data, context) do
    case eval(option, data, context) do
      {:ok, pretty} when is_boolean(pretty) -> {:ok, pretty}
      {:ok, _} -> {:error, Error.new("T0410", "Invalid arguments for $string")}
      error -> error
    end
  end

  defp eval_ordered_value({:object, pairs}, data, context) do
    Enum.reduce_while(pairs, {:ok, %{}, []}, fn {key_ast, value_ast}, {:ok, values, keys} ->
      with {:ok, key} <- eval(key_ast, data, context),
           true <- is_binary(key),
           {:ok, value} <- eval_ordered_value(value_ast, data, context) do
        if Value.undefined?(value) do
          {:cont, {:ok, values, keys}}
        else
          keys = if Map.has_key?(values, key), do: keys, else: [key | keys]
          {:cont, {:ok, Map.put(values, key, value), keys}}
        end
      else
        false -> {:halt, {:error, Error.new("T1003", "Object key must be a string")}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values, keys} ->
        {:ok, {:ordered_object, Enum.map(Enum.reverse(keys), &{&1, values[&1]})}}

      error ->
        error
    end
  end

  defp eval_ordered_value({:array, expressions}, data, context) do
    Enum.reduce_while(expressions, {:ok, []}, fn expression, {:ok, values} ->
      case eval_ordered_value(expression, data, context) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} ->
        {:ok,
         expressions
         |> Enum.zip(Enum.reverse(values))
         |> Enum.flat_map(fn
           {{:array, _}, value} -> [value]
           {_, %Value.Sequence{items: items}} -> items
           {_, value} when is_list(value) -> value
           {_, value} -> if Value.undefined?(value), do: [], else: [value]
         end)}

      error ->
        error
    end
  end

  defp eval_ordered_value(ast, data, context), do: eval(ast, data, context)

  defp eval_binding({:binary, ":=", {:variable, name}, right}, data, context)
       when name not in ["$", "$$"] do
    result =
      case right do
        {:binary, ":=", _, _} ->
          eval_binding(right, data, context)

        _ ->
          case eval(right, data, context) do
            {:ok, value} -> {:ok, value, context}
            error -> error
          end
      end

    case result do
      {:ok, value, next} -> {:ok, value, put_in(next.environment[name], value)}
      error -> error
    end
  end

  defp eval_binding(_, _, _),
    do: {:error, Error.new("S0212", "Binding target must be a variable")}

  defp higher_order("$map", [input, callback], data) do
    items = Value.items(input)
    map_items(items, callback, data, items, 0, [])
  end

  defp higher_order("$filter", [input, callback], data) do
    items = Value.items(input)
    filter_items(items, callback, data, items, 0, [])
  end

  defp higher_order("$reduce", [input, callback], data),
    do: reduce_items(Value.items(input), callback, Value.undefined(), data)

  defp higher_order("$reduce", [input, callback, initial], data),
    do: reduce_items(Value.items(input), callback, initial, data)

  defp higher_order("$sort", [input], data), do: Functions.call("$sort", [input], data)

  defp higher_order("$sort", [input, callback], data) do
    if Value.undefined?(input) do
      {:ok, input}
    else
      input
      |> Value.items()
      |> merge_sort(callback, data)
      |> case do
        {:ok, sorted} -> {:ok, Value.sequence(sorted)}
        error -> error
      end
    end
  end

  defp higher_order("$single", [input], data), do: higher_order("$single", [input, nil], data)

  defp higher_order("$single", [input, callback], data) do
    if Value.undefined?(input) do
      {:ok, Value.undefined()}
    else
      input
      |> Value.items()
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, found} ->
        result =
          if is_nil(callback),
            do: {:ok, true},
            else: invoke_callback(callback, [item, index, Value.items(input)], data)

        case result do
          {:ok, value} ->
            {:cont, {:ok, if(Semantics.boolean(value), do: [item | found], else: found)}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, [item]} -> {:ok, item}
        {:ok, []} -> {:error, Error.new("D3139", "$single found no matching item")}
        {:ok, _} -> {:error, Error.new("D3138", "$single found multiple matching items")}
        error -> error
      end
    end
  end

  defp higher_order("$each", [object, callback], data)
       when is_map(object) and not is_struct(object) do
    object
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, results} ->
      case invoke_callback(callback, [value, key, object], data) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Value.sequence(Enum.reverse(results))}
      error -> error
    end
  end

  defp higher_order("$sift", [object, callback], data)
       when is_map(object) and not is_struct(object) do
    Enum.reduce_while(object, {:ok, %{}}, fn {key, value}, {:ok, result} ->
      case invoke_callback(callback, [value, key, object], data) do
        {:ok, keep} ->
          {:cont,
           {:ok, if(Semantics.boolean(keep), do: Map.put(result, key, value), else: result)}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, result} when map_size(result) == 0 -> {:ok, Value.undefined()}
      other -> other
    end
  end

  defp higher_order("$sift", [objects, callback], data) when is_list(objects) do
    Enum.reduce_while(objects, {:ok, []}, fn object, {:ok, results} ->
      case higher_order("$sift", [object, callback], data) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Value.sequence(Enum.reverse(results))}
      error -> error
    end
  end

  defp higher_order("$sift", [%Value.Sequence{items: objects}, callback], data),
    do: higher_order("$sift", [objects, callback], data)

  defp higher_order("$sift", [_other, _callback], _data), do: {:ok, Value.undefined()}

  defp higher_order(name, _, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}

  defp map_items([], _callback, _data, _items, _index, acc),
    do: {:ok, Value.sequence(Enum.reverse(acc))}

  defp map_items([item | rest], callback, data, items, index, acc) do
    case invoke_indexed_callback(callback, item, index, items, data) do
      {:ok, value} -> map_items(rest, callback, data, items, index + 1, [value | acc])
      error -> error
    end
  end

  defp filter_items([], _callback, _data, _items, _index, acc),
    do: {:ok, Value.sequence(Enum.reverse(acc))}

  defp filter_items([item | rest], callback, data, items, index, acc) do
    case invoke_indexed_callback(callback, item, index, items, data) do
      {:ok, value} ->
        next = if Semantics.boolean(value), do: [item | acc], else: acc
        filter_items(rest, callback, data, items, index + 1, next)

      error ->
        error
    end
  end

  defp invoke_indexed_callback(%Closure{arity: 0} = closure, _item, _index, _items, data),
    do: invoke(closure, [], data)

  defp invoke_indexed_callback(%Closure{arity: 1} = closure, item, _index, _items, data),
    do: invoke(closure, [item], data)

  defp invoke_indexed_callback(%Closure{arity: 2} = closure, item, index, _items, data),
    do: invoke(closure, [item, index], data)

  defp invoke_indexed_callback(%Closure{arity: 3} = closure, item, index, items, data),
    do: invoke(closure, [item, index, items], data)

  defp invoke_indexed_callback(callback, item, index, items, data),
    do: invoke_callback(callback, [item, index, items], data)

  defp reduce_items(items, callback, initial, data) do
    if is_struct(callback, Closure) and length(callback.parameters) < 2 do
      {:error, Error.new("D3050", "$reduce callback requires at least two parameters")}
    else
      do_reduce_items(items, callback, initial, data)
    end
  end

  defp do_reduce_items(items, callback, initial, data) do
    index_offset = if Value.undefined?(initial), do: 1, else: 0

    {first, rest} =
      if Value.undefined?(initial) do
        case items do
          [] -> {Value.undefined(), []}
          [head | tail] -> {head, tail}
        end
      else
        {initial, items}
      end

    rest
    |> Enum.with_index(index_offset)
    |> Enum.reduce_while({:ok, first}, fn {item, index}, {:ok, accumulator} ->
      case invoke_callback(callback, [accumulator, item, index, items], data) do
        {:ok, value} -> {:cont, {:ok, value}}
        error -> {:halt, error}
      end
    end)
  end

  defp invoke_callback(%Closure{arity: 0} = closure, _args, data), do: invoke(closure, [], data)

  defp invoke_callback(%Closure{arity: 1} = closure, [a | _], data),
    do: invoke(closure, [a], data)

  defp invoke_callback(%Closure{arity: 2} = closure, [a, b | _], data),
    do: invoke(closure, [a, b], data)

  defp invoke_callback(%Closure{arity: 3} = closure, [a, b, c | _], data),
    do: invoke(closure, [a, b, c], data)

  defp invoke_callback(%Closure{arity: arity} = closure, args, data),
    do: invoke(closure, Enum.take(args, arity), data)

  defp invoke_callback(%Builtin{name: "$append"} = builtin, [left, right | _], data),
    do: invoke(builtin, [left, right], data)

  defp invoke_callback(%Builtin{} = builtin, [value | _], data),
    do: invoke(builtin, [value], data)

  defp invoke_callback(%Partial{} = partial, [value | _], data),
    do: invoke(partial, [value], data)

  defp invoke_callback(%Composition{} = composition, [value | _], data),
    do: invoke(composition, [value], data)

  defp invoke_callback(_, _, _),
    do: {:error, Error.new("T1006", "Comparator or callback is not a function")}

  defp merge_sort([], _callback, _data), do: {:ok, []}
  defp merge_sort([_] = items, _callback, _data), do: {:ok, items}

  defp merge_sort(items, callback, data) do
    {left, right} = Enum.split(items, div(length(items), 2))

    with {:ok, left} <- merge_sort(left, callback, data),
         {:ok, right} <- merge_sort(right, callback, data),
         do: merge_sorted(left, right, callback, data, [])
  end

  defp merge_sorted([], right, _callback, _data, acc),
    do: {:ok, Enum.reverse(acc, right)}

  defp merge_sorted(left, [], _callback, _data, acc),
    do: {:ok, Enum.reverse(acc, left)}

  defp merge_sorted([a | left] = first, [b | right] = second, callback, data, acc) do
    case invoke_callback(callback, [a, b], data) do
      {:ok, result} ->
        if Semantics.boolean(result),
          do: merge_sorted(first, right, callback, data, [b | acc]),
          else: merge_sorted(left, second, callback, data, [a | acc])

      error ->
        error
    end
  end

  defp invoke_or_partial(function, values, data) do
    if Enum.any?(values, &is_struct(&1, Placeholder)) do
      {:ok, %Partial{function: function, arguments: values}}
    else
      invoke(function, values, data)
    end
  end

  defp with_recursive_bindings(%Closure{references: []} = closure, _environment), do: closure

  defp with_recursive_bindings(%Closure{} = closure, environment) do
    bound =
      Enum.reduce(closure.references, closure.environment, fn name, acc ->
        case Map.fetch(environment, name) do
          {:ok, value}
          when not is_map_key(acc, name) and
                 (is_struct(value, Closure) or is_struct(value, Builtin) or
                    is_struct(value, Partial)) ->
            Map.put(acc, name, value)

          _ ->
            acc
        end
      end)

    %{closure | environment: bound}
  end

  defp with_recursive_bindings(function, _environment), do: function

  defp referenced_variables(ast), do: referenced_variables(ast, MapSet.new())

  defp expand_closure_references(references, environment),
    do: expand_closure_references(MapSet.to_list(references), environment, references)

  defp expand_closure_references([], _environment, references), do: MapSet.to_list(references)

  defp expand_closure_references([name | rest], environment, references) do
    dependencies =
      case Map.get(environment, name) do
        %Closure{references: names} -> names
        _ -> []
      end

    new = Enum.reject(dependencies, &MapSet.member?(references, &1))
    references = Enum.reduce(new, references, &MapSet.put(&2, &1))
    expand_closure_references(rest ++ new, environment, references)
  end

  defp referenced_variables({:variable, name}, acc), do: MapSet.put(acc, name)

  defp referenced_variables(ast, acc) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.reduce(acc, &referenced_variables/2)

  defp referenced_variables(ast, acc) when is_list(ast),
    do: Enum.reduce(ast, acc, &referenced_variables/2)

  defp referenced_variables(_, acc), do: acc

  defp invoke(%Closure{} = closure, values, data) do
    depth = Process.get({__MODULE__, :closure_depth}, 0)

    if depth >= Process.get({__MODULE__, :max_function_depth}, 1024) do
      {:error, Error.new("U1001", "Function recursion limit exceeded")}
    else
      Process.put({__MODULE__, :closure_depth}, depth + 1)

      try do
        invoke_closure_loop(closure, values, data, 0)
      after
        if depth == 0,
          do: Process.delete({__MODULE__, :closure_depth}),
          else: Process.put({__MODULE__, :closure_depth}, depth)
      end
    end
  end

  defp invoke(%Builtin{name: name}, values, data)
       when name in ["$map", "$filter", "$reduce", "$single", "$each", "$sift", "$sort"],
       do: higher_order(name, values, data)

  defp invoke(%Builtin{name: name}, values, data), do: Functions.call(name, values, data)

  defp invoke(%Composition{first: first, second: second}, values, data) do
    with {:ok, intermediate} <- invoke(first, values, data),
         do: invoke(second, [intermediate], data)
  end

  defp invoke(%Transform{} = transform, [input], _data), do: apply_transform(transform, input)

  defp invoke(%Partial{function: function, arguments: arguments}, values, data) do
    {filled, remaining} =
      Enum.map_reduce(arguments, values, fn
        %Placeholder{}, [value | tail] -> {value, tail}
        %Placeholder{} = placeholder, [] -> {placeholder, []}
        fixed, rest -> {fixed, rest}
      end)

    invoke_or_partial(function, filled ++ remaining, data)
  end

  defp invoke(%Regex{} = pattern, [value], _data) when is_binary(value) do
    case Regex.run(pattern, value, return: :index) do
      nil ->
        {:ok, Value.undefined()}

      [{index, length} | captures] ->
        groups =
          Enum.map(captures, fn
            {-1, _} -> ""
            {start, size} -> binary_part(value, start, size)
          end)

        {:ok,
         %{"match" => binary_part(value, index, length), "index" => index, "groups" => groups}}
    end
  end

  defp invoke(_, _, _),
    do: {:error, Error.new("T1006", "Value is not a callable function or arity is invalid")}

  defp invoke_closure_loop(_closure, _values, _data, steps) when steps >= 100_000,
    do: {:error, Error.new("U1001", "Function iteration limit exceeded")}

  defp invoke_closure_loop(
         %Closure{parameters: parameters, body: body} = closure,
         values,
         data,
         steps
       ) do
    case Signature.bind(closure.signature, parameters, values, data) do
      {:ok, bound} ->
        bindings = bind_parameters(parameters, bound)
        context = %{root: closure.root, environment: Map.merge(closure.environment, bindings)}

        case tail_expression(body, closure.context_value, context) do
          {:tail, %Closure{} = next, arguments} ->
            invoke_closure_loop(next, arguments, next.context_value, steps + 1)

          {:eval, ast} ->
            eval(ast, closure.context_value, context)

          error ->
            error
        end

      {:undefined} ->
        {:ok, Value.undefined()}

      error ->
        error
    end
  end

  defp bind_parameters([], []), do: %{}
  defp bind_parameters([name], [value]), do: %{name => value}
  defp bind_parameters([a, b], [first, second]), do: %{a => first, b => second}

  defp bind_parameters([a, b, c], [first, second, third]),
    do: %{a => first, b => second, c => third}

  defp bind_parameters(parameters, values), do: Enum.zip(parameters, values) |> Map.new()

  defp tail_expression({:conditional, test, yes, no}, data, context) do
    case eval(test, data, context) do
      {:ok, value} ->
        tail_expression(if(Semantics.boolean(value), do: yes, else: no), data, context)

      error ->
        error
    end
  end

  defp tail_expression({:call, {:variable, name}, args} = ast, data, context) do
    case Map.get(context.environment, name) do
      %Closure{} = closure ->
        case eval_list(args, data, context) do
          {:ok, values} -> {:tail, with_recursive_bindings(closure, context.environment), values}
          error -> error
        end

      _ ->
        {:eval, ast}
    end
  end

  defp tail_expression(ast, _data, _context), do: {:eval, ast}

  defp match_callback(matcher, value) do
    matcher = with_recursive_bindings(matcher, %{"$match" => matcher})

    with {:ok, first} <- invoke(matcher, [value], value),
         do: match_callback_results(first, [], 0)
  end

  defp match_callback_results(_result, _acc, count) when count >= 100_000,
    do: {:error, Error.new("U1001", "Matcher iteration limit exceeded")}

  defp match_callback_results(result, acc, count) do
    cond do
      Value.undefined?(result) ->
        {:ok, Value.sequence(Enum.reverse(acc))}

      is_map(result) and is_binary(result["match"]) and is_number(result["start"]) and
          is_list(result["groups"]) ->
        entry = %{
          "match" => result["match"],
          "index" => result["start"],
          "groups" => result["groups"]
        }

        case result["next"] do
          %Closure{} = next ->
            with {:ok, subsequent} <- invoke(next, [], next.context_value),
                 do: match_callback_results(subsequent, [entry | acc], count + 1)

          _ ->
            {:ok, Value.sequence(Enum.reverse([entry | acc]))}
        end

      true ->
        {:error, Error.new("T1010", "Matcher did not return a match object")}
    end
  end

  defp callable?(value),
    do:
      is_struct(value, Closure) or is_struct(value, Builtin) or is_struct(value, Partial) or
        is_struct(value, Composition) or is_struct(value, Transform) or is_struct(value, Regex)

  defp apply_transform(%Transform{} = transform, input) do
    context = %{root: input, environment: transform.environment}

    references =
      transform.pattern
      |> selected_paths([{[], input}], context)
      |> Enum.flat_map(&expand_reference/1)
      |> Enum.filter(fn {_path, value} -> is_map(value) and not is_struct(value) end)
      |> Enum.uniq_by(&elem(&1, 0))

    if disjoint_references?(references) do
      apply_disjoint_transform(transform, input, context, references)
    else
      apply_sequential_transform(transform, input, context, references)
    end
  end

  defp disjoint_references?([]), do: true

  defp disjoint_references?([{path, _} | rest]),
    do: Enum.all?(rest, fn {candidate, _} -> length(candidate) == length(path) end)

  defp apply_disjoint_transform(_transform, input, _context, []), do: {:ok, input}

  defp apply_disjoint_transform(transform, input, context, references) do
    Enum.reduce_while(references, {:ok, %{}}, fn {path, selected}, {:ok, trie} ->
      case transformed_value(transform, selected, context) do
        {:ok, changed} -> {:cont, {:ok, insert_update(trie, path, changed)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, trie} -> {:ok, apply_updates(input, trie)}
      error -> error
    end
  end

  defp apply_sequential_transform(transform, input, context, references) do
    Enum.reduce_while(references, {:ok, input}, fn {path, _}, {:ok, document} ->
      selected = get_path(document, path)

      case transformed_value(transform, selected, context) do
        {:ok, changed} -> {:cont, {:ok, put_path(document, path, changed)}}
        error -> {:halt, error}
      end
    end)
  end

  defp transformed_value(transform, selected, context) do
    with {:ok, update} <- eval(transform.update, selected, context),
         {:ok, update} <- transform_update(update),
         {:ok, delete} <- transform_delete(transform.delete, selected, context),
         do: {:ok, selected |> Map.merge(update) |> Map.drop(delete)}
  end

  defp insert_update(_trie, [], changed), do: {:replace, changed}

  defp insert_update(trie, [key | rest], changed) do
    child = Map.get(trie, key, %{})
    Map.put(trie, key, insert_update(child, rest, changed))
  end

  defp apply_updates(_input, {:replace, changed}), do: changed

  defp apply_updates(input, trie) when is_map(input),
    do:
      Enum.reduce(trie, input, fn {key, child}, acc ->
        Map.update!(acc, key, &apply_updates(&1, child))
      end)

  defp apply_updates(input, trie) when is_list(input),
    do: apply_updates_list(input, trie, 0, [])

  defp apply_updates_list([], _trie, _index, acc), do: Enum.reverse(acc)

  defp apply_updates_list([value | rest], trie, index, acc) do
    updated =
      case Map.fetch(trie, index) do
        {:ok, child} -> apply_updates(value, child)
        :error -> value
      end

    apply_updates_list(rest, trie, index + 1, [updated | acc])
  end

  defp transform_update(update) when is_map(update) and not is_struct(update), do: {:ok, update}
  defp transform_update(update) when is_struct(update, Value.Undefined), do: {:ok, %{}}
  defp transform_update(_), do: {:error, Error.new("T2011", "Transform update must be an object")}

  defp transform_delete(nil, _selected, _context), do: {:ok, []}

  defp transform_delete(ast, selected, context) do
    case eval(ast, selected, context) do
      {:ok, value} when is_binary(value) ->
        {:ok, [value]}

      {:ok, values} when is_list(values) ->
        if Enum.all?(values, &is_binary/1),
          do: {:ok, values},
          else: {:error, Error.new("T2012", "Transform delete must contain strings")}

      {:ok, value} when is_struct(value, Value.Undefined) ->
        {:ok, []}

      {:ok, _} ->
        {:error, Error.new("T2012", "Transform delete must contain strings")}

      error ->
        error
    end
  end

  defp selected_paths({:variable, "$"}, refs, _context), do: refs

  defp selected_paths({:block, [ast]}, refs, context),
    do: selected_paths(ast, refs, context)

  defp selected_paths({:path, left, right}, refs, context),
    do: selected_paths(right, selected_paths(left, refs, context), context)

  defp selected_paths({:compiled_path, left, right, _}, refs, context),
    do: selected_paths(right, selected_paths(left, refs, context), context)

  defp selected_paths({:name, name}, refs, _context) do
    refs
    |> Enum.flat_map(&expand_reference/1)
    |> Enum.flat_map(fn
      {path, map} when is_map(map) and not is_struct(map) ->
        if Map.has_key?(map, name), do: [{path ++ [name], Map.get(map, name)}], else: []

      _ ->
        []
    end)
  end

  defp selected_paths({:filter, left, predicate}, refs, context) do
    candidates = left |> selected_paths(refs, context) |> Enum.flat_map(&expand_reference/1)
    count = length(candidates)

    candidates
    |> Enum.with_index()
    |> Enum.filter(fn {{_path, value}, index} ->
      case eval(predicate, value, context) do
        {:ok, result} -> predicate_matches?(result, index, count)
        _ -> false
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp selected_paths(:wildcard, refs, _context) do
    refs
    |> Enum.flat_map(&expand_reference/1)
    |> Enum.flat_map(fn
      {path, map} when is_map(map) and not is_struct(map) ->
        Enum.map(map, fn {key, value} -> {path ++ [key], value} end)

      _ ->
        []
    end)
  end

  defp selected_paths(:descendants, refs, _context),
    do: refs ++ Enum.flat_map(refs, &descendant_references/1)

  defp selected_paths(_, _refs, _context), do: []

  defp descendant_references({path, map}) when is_map(map) and not is_struct(map) do
    Enum.flat_map(map, fn {key, value} ->
      reference = {path ++ [key], value}
      [reference | descendant_references(reference)]
    end)
  end

  defp descendant_references({path, values}) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      reference = {path ++ [index], value}
      [reference | descendant_references(reference)]
    end)
  end

  defp descendant_references(_), do: []

  defp expand_reference({path, values}) when is_list(values),
    do: Enum.with_index(values) |> Enum.map(fn {value, index} -> {path ++ [index], value} end)

  defp expand_reference(reference), do: [reference]

  defp get_path(value, []), do: value
  defp get_path(map, [key | tail]) when is_map(map), do: get_path(Map.fetch!(map, key), tail)
  defp get_path(list, [index | tail]) when is_list(list), do: get_path(Enum.at(list, index), tail)

  defp put_path(_old, [], value), do: value

  defp put_path(map, [key | tail], value) when is_map(map),
    do: Map.update!(map, key, &put_path(&1, tail, value))

  defp put_path(list, [index | tail], value) when is_list(list),
    do: List.update_at(list, index, &put_path(&1, tail, value))

  defp evaluate_source(source, data, context) do
    case Jexata.Parser.parse(source) do
      {:ok, ast} ->
        case eval(ast, data, %{context | root: data}) do
          {:error, %Error{code: code}} when code in ["T1006", "T1005"] ->
            {:error, Error.new("D3121", "Error evaluating expression supplied to $eval")}

          result ->
            result
        end

      {:error, _} ->
        {:error, Error.new("D3120", "Invalid expression supplied to $eval")}
    end
  end

  defp replace_callback(value, pattern, callback, limit, data) do
    if Regex.match?(pattern, "") do
      {:error, Error.new("D1004", "Regex must not match an empty string")}
    else
      matches = Regex.scan(pattern, value, return: :index)
      matches = if limit == :all, do: matches, else: Enum.take(matches, limit)

      Enum.reduce_while(matches, {:ok, [], 0}, fn [{start, size} | captures],
                                                  {:ok, acc, cursor} ->
        groups =
          Enum.map(captures, fn
            {-1, _} -> ""
            {index, length} -> binary_part(value, index, length)
          end)

        match = %{
          "match" => binary_part(value, start, size),
          "index" => start,
          "groups" => groups
        }

        case invoke_callback(callback, [match], data) do
          {:ok, replacement} when is_binary(replacement) ->
            prefix = binary_part(value, cursor, start - cursor)
            {:cont, {:ok, [acc, prefix, replacement], start + size}}

          {:ok, _} ->
            {:halt, {:error, Error.new("D3012", "Replacement function must return a string")}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, parts, cursor} ->
          {:ok,
           IO.iodata_to_binary([parts, binary_part(value, cursor, byte_size(value) - cursor)])}

        error ->
          error
      end
    end
  end

  defp eval_each(items, {:name, name}, _root, flatten_arrays?, keep_array?) do
    values =
      Enum.reduce(items, [], fn item, acc ->
        selected = Semantics.select(item, name)
        selected_values = if flatten_arrays?, do: Value.items(selected), else: [selected]
        Enum.reduce(selected_values, acc, fn value, acc -> [value | acc] end)
      end)

    {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
  end

  defp eval_each(items, {:variable, _} = ast, context, _flatten_arrays?, keep_array?) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, values} ->
      case eval(ast, item, context) do
        {:ok, []} -> {:cont, {:ok, values}}
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
      error -> error
    end
  end

  defp eval_each(items, ast, root, _flatten_arrays?, keep_array?) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case eval(ast, item, root) do
        {:ok, value} ->
          {:cont, {:ok, [value | acc]}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
      error -> error
    end
  end

  defp eval_list(nodes, data, root) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case eval(node, data, root) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp eval_boolean(ast, data, root) do
    with {:ok, value} <- eval(ast, data, root), do: {:ok, Semantics.boolean(value)}
  end

  defp binary("<", a, b) when is_number(a) and is_number(b), do: {:ok, a < b}
  defp binary("<=", a, b) when is_number(a) and is_number(b), do: {:ok, a <= b}
  defp binary(">", a, b) when is_number(a) and is_number(b), do: {:ok, a > b}
  defp binary(">=", a, b) when is_number(a) and is_number(b), do: {:ok, a >= b}

  defp binary("=", a, b)
       when not is_struct(a, Value.Undefined) and not is_struct(b, Value.Undefined),
       do: {:ok, a == b}

  defp binary("!=", a, b)
       when not is_struct(a, Value.Undefined) and not is_struct(b, Value.Undefined),
       do: {:ok, a != b}

  defp binary("+", a, b)
       when is_integer(a) and is_integer(b) and abs(a) <= 9_007_199_254_740_991 and
              abs(b) <= 9_007_199_254_740_991,
       do: {:ok, number_result(a + b)}

  defp binary("-", a, b)
       when is_integer(a) and is_integer(b) and abs(a) <= 9_007_199_254_740_991 and
              abs(b) <= 9_007_199_254_740_991,
       do: {:ok, number_result(a - b)}

  defp binary("*", a, b)
       when is_integer(a) and is_integer(b) and abs(a) <= 9_007_199_254_740_991 and
              abs(b) <= 9_007_199_254_740_991,
       do: {:ok, number_result(a * b)}

  defp binary("%", a, b)
       when is_integer(a) and is_integer(b) and b != 0 and
              abs(a) <= 9_007_199_254_740_991 and abs(b) <= 9_007_199_254_740_991,
       do: {:ok, number_result(rem(a, b))}

  defp binary("/", a, b) when is_number(a) and is_number(b) and b == 0,
    do: {:error, Error.new("D1001", "Division by zero")}

  defp binary("/", a, b) when is_number(a) and is_number(b) do
    {:ok, a / b}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  defp binary("+", a, b) when is_number(a) and is_number(b) do
    {:ok, number_result(a + b)}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  defp binary("-", a, b) when is_number(a) and is_number(b) do
    {:ok, number_result(a - b)}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  defp binary("*", a, b) when is_number(a) and is_number(b) do
    {:ok, number_result(a * b)}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  defp binary(op, a, b) when op in ["<", "<=", ">", ">="] do
    cond do
      not order_operand?(a) or not order_operand?(b) ->
        {:error, Error.new("T2010", "Ordering requires strings or numbers")}

      Value.undefined?(a) or Value.undefined?(b) ->
        {:ok, Value.undefined()}

      (is_number(a) and is_number(b)) or (is_binary(a) and is_binary(b)) ->
        {:ok, Semantics.compare(op, a, b)}

      true ->
        {:error, Error.new("T2009", "Ordering operands must have the same type")}
    end
  end

  defp binary(op, a, b) when op in ["+", "-", "*", "/", "%"] do
    cond do
      not is_number(a) and not Value.undefined?(a) ->
        {:error, Error.new("T2001", "Left arithmetic operand must be a number")}

      not is_number(b) and not Value.undefined?(b) ->
        {:error, Error.new("T2002", "Right arithmetic operand must be a number")}

      Value.undefined?(a) or Value.undefined?(b) ->
        {:ok, Value.undefined()}

      true ->
        case {op, b} do
          {"/", zero} when zero == 0 -> {:error, Error.new("D1001", "Division by zero")}
          {"%", zero} when zero == 0 -> {:error, Error.new("D1001", "Division by zero")}
          {"+", _} -> {:ok, number_result(a + b)}
          {"-", _} -> {:ok, number_result(a - b)}
          {"*", _} -> {:ok, number_result(a * b)}
          {"/", _} -> {:ok, a / b}
          {"%", _} when is_integer(a) and is_integer(b) -> {:ok, number_result(rem(a, b))}
          {"%", _} -> {:ok, :math.fmod(a, b)}
        end
    end
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  defp binary("&", a, b), do: {:ok, string(a) <> string(b)}

  defp binary("..", a, b) do
    cond do
      Value.undefined?(a) and not is_integer(b) ->
        {:error, Error.new("T2004", "Range end must be an integer")}

      Value.undefined?(b) and not is_integer(a) ->
        {:error, Error.new("T2003", "Range start must be an integer")}

      Value.undefined?(a) or Value.undefined?(b) ->
        {:ok, Value.undefined()}

      not is_integer(a) ->
        {:error, Error.new("T2003", "Range start must be an integer")}

      not is_integer(b) ->
        {:error, Error.new("T2004", "Range end must be an integer")}

      b - a + 1 > 100_000 ->
        {:error, Error.new("D2014", "Range exceeds the configured limit")}

      a > b ->
        {:ok, Value.undefined()}

      true ->
        {:ok, Value.sequence(Enum.to_list(a..b))}
    end
  end

  defp binary("in", a, b), do: {:ok, Semantics.compare("in", a, b)}

  defp binary(op, a, b)
       when op in ["=", "!="] and
              (is_struct(a, Value.Undefined) or is_struct(b, Value.Undefined)),
       do: {:ok, false}

  defp binary(_, a, b) when is_struct(a, Value.Undefined) or is_struct(b, Value.Undefined),
    do: {:ok, Value.undefined()}

  defp binary(op, a, b) when op in ["=", "!=", "in"], do: {:ok, Semantics.compare(op, a, b)}

  defp binary(op, _, _), do: {:error, Error.new("T1007", "Unsupported operator #{op}")}

  defp order_operand?(value),
    do: is_number(value) or is_binary(value) or Value.undefined?(value)

  defp number_result(value) when is_integer(value) and abs(value) > 9_007_199_254_740_991,
    do: value * 1.0

  defp number_result(value), do: value

  defp string(nil), do: "null"
  defp string(true), do: "true"
  defp string(false), do: "false"
  defp string(value) when is_binary(value), do: value
  defp string(value) when is_number(value), do: Semantics.number_string(value)
  defp string(value) when is_struct(value, Value.Undefined), do: ""

  defp string(value) do
    {:ok, result} = Jexata.Functions.String.call("$string", [value])
    result
  end

  defp group_items(items, key_ast, context) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, groups} ->
      case eval(key_ast, item, context) do
        {:ok, key} when is_binary(key) ->
          {:cont, {:ok, Map.update(groups, key, [item], &[item | &1])}}

        {:ok, _} ->
          {:halt, {:error, Error.new("T1003", "Group key must be a string")}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp predicate_matches?(value, index, count) when is_number(value) do
    target = floor(value)
    index == if(target < 0, do: count + target, else: target)
  end

  defp predicate_matches?(values, index, count) when is_list(values) and values != [] do
    if Enum.all?(values, &is_number/1),
      do: Enum.any?(values, &predicate_matches?(&1, index, count)),
      else: Semantics.boolean(values)
  end

  defp predicate_matches?(value, _index, _count), do: Semantics.boolean(value)

  defp boolean_predicate?({:literal, value}) when is_boolean(value), do: true

  defp boolean_predicate?({:binary, op, _, _})
       when op in ["=", "!=", "<", "<=", ">", ">=", "in", "and", "or"],
       do: true

  defp boolean_predicate?(_), do: false

  defp eval_sort_keys(terms, item, context) do
    Enum.reduce_while(terms, {:ok, []}, fn {direction, ast}, {:ok, keys} ->
      case eval(ast, item, context) do
        {:ok, value}
        when is_number(value) or is_binary(value) or is_struct(value, Value.Undefined) ->
          {:cont, {:ok, [{direction, value} | keys]}}

        {:ok, _} ->
          {:halt, {:error, Error.new("T2008", "Sort key must be a number or string")}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      error -> error
    end
  end

  defp compare_sort_keys([], []), do: true

  defp compare_sort_keys([{direction, left} | rest_a], [{_, right} | rest_b]) do
    cond do
      Value.undefined?(left) and Value.undefined?(right) -> compare_sort_keys(rest_a, rest_b)
      Value.undefined?(left) -> false
      Value.undefined?(right) -> true
      left == right -> compare_sort_keys(rest_a, rest_b)
      direction == :asc -> left < right
      true -> left > right
    end
  end

  defp validate_sort_keys([]), do: :ok

  defp validate_sort_keys(decorated) do
    key_count = decorated |> hd() |> elem(1) |> length()

    if Enum.any?(0..(key_count - 1), fn index ->
         decorated
         |> Enum.map(fn {_, keys} -> keys |> Enum.at(index) |> elem(1) end)
         |> Enum.reject(&Value.undefined?/1)
         |> Enum.map(fn value -> if is_number(value), do: :number, else: :string end)
         |> Enum.uniq()
         |> length() > 1
       end),
       do: {:error, Error.new("T2007", "Sort keys have incompatible types")},
       else: :ok
  end

  defp descendants(value) when is_list(value), do: Enum.flat_map(value, &descendants/1)

  defp descendants(value) when is_map(value) and not is_struct(value) do
    [value | Enum.flat_map(value, fn {_key, child} -> descendants(child) end)]
  end

  defp descendants(value), do: [value]

  defp contextual_path_call({:call, {:variable, name}, args} = call) do
    needs_context =
      (name in ["$substringBefore", "$substringAfter", "$contains", "$split", "$match", "$pad"] and
         length(args) == 1) or
        (name == "$substring" and length(args) == 1) or
        (name == "$replace" and length(args) == 2)

    if needs_context,
      do: {:call, {:variable, name}, [{:variable, "$"} | args]},
      else: call
  end

  defp contextual_path_call(other), do: other
end
