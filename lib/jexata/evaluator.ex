defmodule Jexata.Evaluator do
  @moduledoc false
  alias Jexata.{Error, Functions, Semantics}
  alias Jexata.Runtime.{Builtin, Closure, Composition, Partial, Signature, Transform, Value}
  alias Jexata.Runtime.Partial.Placeholder

  @spec evaluate(Jexata.AST.t(), term()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(ast, :undefined) do
    missing = Value.undefined()
    eval(ast, missing, %{root: missing, environment: %{}})
  end

  def evaluate(ast, data), do: eval(ast, data, %{root: data, environment: %{}})

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

  defp eval({:path, left, right}, data, root) do
    left =
      if match?({:literal, name} when is_binary(name), left),
        do: {:name, elem(left, 1)},
        else: left

    right =
      if match?({:literal, name} when is_binary(name), right),
        do: {:name, elem(right, 1)},
        else: right

    right = contextual_path_call(right)

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

  defp eval({:group, left, pairs}, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, result} ->
        case group_items(Value.items(source), key_ast, context) do
          {:ok, groups} ->
            Enum.reduce_while(groups, {:ok, result}, fn {key, items}, {:ok, acc} ->
              case eval(value_ast, Enum.reverse(items), context) do
                {:ok, value} ->
                  {:cont,
                   {:ok, if(Value.undefined?(value), do: acc, else: Map.put(acc, key, value))}}

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

  defp eval({:keep_array, ast}, data, context) do
    with {:ok, value} <- eval(ast, data, context),
         do: {:ok, Value.sequence(Value.items(value), true)}
  end

  defp eval({:filter, left, predicate}, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      items = Value.items(source)
      count = length(items)

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

  defp eval({:lambda, parameters, signature, body}, _, context) do
    {:ok,
     %Closure{
       parameters: parameters,
       body: body,
       environment: context.environment,
       root: context.root,
       signature: signature
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
            do: {:error, Error.new("T1005", "Unknown function")},
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
    input
    |> Value.items()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case invoke_callback(callback, [item, index, Value.items(input)], data) do
        {:ok, value} ->
          {:cont, {:ok, [value | acc]}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values))}
      error -> error
    end
  end

  defp higher_order("$filter", [input, callback], data) do
    input
    |> Value.items()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case invoke_callback(callback, [item, index, Value.items(input)], data) do
        {:ok, value} -> {:cont, {:ok, if(Semantics.boolean(value), do: [item | acc], else: acc)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values))}
      error -> error
    end
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
      |> Enum.reduce_while({:ok, []}, fn item, {:ok, sorted} ->
        case insert_sorted(item, sorted, callback, data) do
          {:ok, next} -> {:cont, {:ok, next}}
          error -> {:halt, error}
        end
      end)
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

  defp reduce_items(items, callback, initial, data) do
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
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, first}, fn {item, index}, {:ok, accumulator} ->
      case invoke_callback(callback, [accumulator, item, index, items], data) do
        {:ok, value} -> {:cont, {:ok, value}}
        error -> {:halt, error}
      end
    end)
  end

  defp invoke_callback(%Closure{parameters: parameters} = closure, args, data),
    do: invoke(closure, Enum.take(args, length(parameters)), data)

  defp invoke_callback(%Builtin{} = builtin, [value | _], data),
    do: invoke(builtin, [value], data)

  defp invoke_callback(%Partial{} = partial, [value | _], data),
    do: invoke(partial, [value], data)

  defp invoke_callback(%Composition{} = composition, [value | _], data),
    do: invoke(composition, [value], data)

  defp invoke_callback(_, _, _),
    do: {:error, Error.new("T1006", "Comparator or callback is not a function")}

  defp insert_sorted(item, [], _callback, _data), do: {:ok, [item]}

  defp insert_sorted(item, [head | tail] = sorted, callback, data) do
    case invoke_callback(callback, [head, item], data) do
      {:ok, result} ->
        if Semantics.boolean(result) do
          {:ok, [item | sorted]}
        else
          with {:ok, rest} <- insert_sorted(item, tail, callback, data),
               do: {:ok, [head | rest]}
        end

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

  defp with_recursive_bindings(%Closure{} = closure, environment) do
    additions =
      Map.filter(environment, fn {name, value} ->
        not Map.has_key?(closure.environment, name) and
          (is_struct(value, Closure) or is_struct(value, Builtin) or is_struct(value, Partial))
      end)

    %{closure | environment: Map.merge(additions, closure.environment)}
  end

  defp with_recursive_bindings(function, _environment), do: function

  defp invoke(%Closure{parameters: parameters, body: body} = closure, values, data) do
    depth = Process.get({__MODULE__, :closure_depth}, 0)

    if depth >= 1024 do
      {:error, Error.new("U1001", "Function recursion limit exceeded")}
    else
      Process.put({__MODULE__, :closure_depth}, depth + 1)

      try do
        case Signature.bind(closure.signature, parameters, values, data) do
          {:ok, bound} ->
            bindings = Enum.zip(parameters, bound) |> Map.new()
            context = %{root: closure.root, environment: Map.merge(closure.environment, bindings)}
            eval(body, data, context)

          {:undefined} ->
            {:ok, Value.undefined()}

          error ->
            error
        end
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

  defp callable?(value),
    do:
      is_struct(value, Closure) or is_struct(value, Builtin) or is_struct(value, Partial) or
        is_struct(value, Composition) or is_struct(value, Transform) or is_struct(value, Regex)

  defp apply_transform(%Transform{} = transform, input) do
    context = %{root: input, environment: transform.environment}

    paths =
      transform.pattern
      |> selected_paths([{[], input}], context)
      |> Enum.flat_map(&expand_reference/1)
      |> Enum.filter(fn {_path, value} -> is_map(value) and not is_struct(value) end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()

    Enum.reduce_while(paths, {:ok, input}, fn path, {:ok, document} ->
      selected = get_path(document, path)

      with {:ok, update} <- eval(transform.update, selected, context),
           {:ok, update} <- transform_update(update),
           {:ok, delete} <- transform_delete(transform.delete, selected, context) do
        changed = selected |> Map.merge(update) |> Map.drop(delete)
        {:cont, {:ok, put_path(document, path, changed)}}
      else
        error -> {:halt, error}
      end
    end)
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

  defp selected_paths({:path, left, right}, refs, context),
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

  defp eval_each(items, ast, root, flatten_arrays?, keep_array?) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case eval(ast, item, root) do
        {:ok, value} ->
          values =
            if flatten_arrays? and match?({:name, _}, ast),
              do: Value.items(value),
              else: [value]

          {:cont, {:ok, Enum.reverse(values) ++ acc}}

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
