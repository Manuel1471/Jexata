defmodule Jexata.Evaluator do
  @moduledoc false
  alias Jexata.{AST, Error, Functions, Semantics}
  alias Jexata.Evaluator.{Ancestry, Grouping, HigherOrder, IndexBindings, Operators, Transforms}

  import Jexata.Evaluator.IndexBindings,
    only: [indexed_path?: 1, keep_array?: 1, predicate_matches?: 3]

  alias Jexata.Runtime.{Builtin, Closure, Composition, Partial, Signature, Transform, Value}
  alias Jexata.Runtime.LimitedRegex
  alias Jexata.Runtime.Partial.Placeholder

  @spec evaluate(Jexata.AST.t(), term()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(ast, data), do: evaluate(ast, data, %{})

  @spec evaluate(Jexata.AST.t(), term(), map()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(ast, data, environment, max_function_depth)
      when is_integer(max_function_depth) and max_function_depth > 0 do
    key = {__MODULE__, :closure_depth_state}
    prior = Process.get(key)
    depth = if prior == nil, do: 0, else: elem(prior, 0)
    Process.put(key, {depth, max_function_depth})

    try do
      evaluate(ast, data, environment)
    after
      if prior == nil, do: Process.delete(key), else: Process.put(key, prior)
    end
  end

  def evaluate(ast, :undefined, environment) do
    missing = Value.undefined()
    evaluate_root(ast, missing, environment)
  end

  def evaluate(ast, data, environment), do: evaluate_root(ast, data, environment)

  defp evaluate_root({:parent_mode, ast}, data, environment),
    do: eval(ast, data, %{root: data, environment: environment, parent_mode: true})

  defp evaluate_root(ast, data, environment),
    do: eval(ast, data, %{root: data, environment: environment, parent_mode: false})

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

  defp eval({:call, :parent, _}, _, _),
    do: {:error, Error.new("T1006", "Parent value is not callable")}

  defp eval(:parent, _, %{environment: environment}) do
    case Ancestry.pop(environment) do
      {:ok, parent, _} -> {:ok, parent}
      :error -> {:error, Error.new("S0217", "No parent context is available")}
    end
  end

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
         do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)), keep_array?(elem(path, 1)))}
  end

  defp eval({:compiled_path, left, right, false} = path, data, context) do
    if Map.get(context, :parent_mode, false) do
      with {:ok, frames} <- eval_indexed(path, data, context),
           do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)))}
    else
      eval_path_steps(left, right, data, context)
    end
  end

  defp eval({:path, left, _} = path, data, context) do
    if indexed_path?(left) or Map.get(context, :parent_mode, false) do
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

  defp eval({:focus_bind, _, _} = path, data, context) do
    with {:ok, frames} <- eval_indexed(path, data, context),
         do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)))}
  end

  defp eval({:group, left, pairs}, data, context) do
    if indexed_path?(left) or Map.get(context, :parent_mode, false) do
      with {:ok, frames} <- eval_indexed(left, data, context),
           do: Grouping.run(frames, pairs, context, &eval/3)
    else
      with {:ok, source} <- eval(left, data, context) do
        if source == [] and left == {:variable, "$$"},
          do: {:ok, %{}},
          else: Grouping.run_plain(Value.items(source), pairs, context, &eval/3)
      end
    end
  end

  defp eval({:sort, left, terms}, data, context) do
    if indexed_path?(left) or Map.get(context, :parent_mode, false) do
      with {:ok, frames} <- eval_indexed({:sort, left, terms}, data, context),
           do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)))}
    else
      eval_regular_sort(left, terms, data, context)
    end
  end

  defp eval({:keep_array, {:array, _} = ast}, data, context) do
    with {:ok, value} <- eval(ast, data, context),
         do: {:ok, Value.sequence([value], true)}
  end

  defp eval({:keep_array, ast}, data, context) do
    with {:ok, value} <- eval(ast, data, context),
         do: {:ok, Value.sequence(Value.items(value), true)}
  end

  defp eval({:filter, left, predicate}, data, root) do
    eval_filter_or_indexed(left, predicate, boolean_predicate?(predicate), data, root)
  end

  defp eval({:compiled_filter, left, predicate, boolean?}, data, root) do
    eval_filter_or_indexed(left, predicate, boolean?, data, root)
  end

  defp eval({:array, expressions}, data, root) do
    eval_array_items(expressions, data, root, [])
  end

  defp eval({:constant_array, values}, _data, _context), do: {:ok, values}

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
          if placeholder_args?(values),
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

  defp eval({:compiled_lambda, parameters, signature, body, references, leaf?}, data, context) do
    {:ok,
     %Closure{
       parameters: parameters,
       arity: length(parameters),
       body: body,
       environment: context.environment,
       root: context.root,
       context_value: data,
       signature: signature,
       references: expand_closure_references(MapSet.new(references), context.environment),
       leaf?: leaf?
     }}
  end

  defp eval({:binary, op, left, right}, data, root) do
    with {:ok, a} <- eval(left, data, root),
         {:ok, b} <- eval(right, data, root) do
      Operators.binary(op, a, b)
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
      if placeholder_args?(values) do
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
          if placeholder_args?(values) do
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
          if placeholder_args?(values) do
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
          if placeholder_args?(values) do
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
      partial? = placeholder_args?(values)

      if partial? and Value.undefined?(function) do
        code =
          case target do
            {:name, name} -> if Functions.supported?("$" <> name), do: "T1007", else: "T1008"
            _ -> "T1007"
          end

        {:error, Error.new(code, "Partial application requires a function")}
      else
        if partial? and not callable?(function) do
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
                data,
                partial?
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

  defp eval_filter_or_indexed(left, predicate, boolean?, data, context) do
    if indexed_path?(left) or Map.get(context, :parent_mode, false) do
      with {:ok, frames} <- eval_indexed_filter(left, predicate, boolean?, data, context),
           do: {:ok, Value.sequence(Enum.map(frames, &elem(&1, 0)), keep_array?(left))}
    else
      eval_filter(left, predicate, boolean?, data, context)
    end
  end

  defp eval_filter(left, {:literal, index}, _boolean?, data, root) when is_integer(index) do
    eval_index_filter(left, index, data, root)
  end

  defp eval_filter(left, {:negate, {:literal, index}}, _boolean?, data, root)
       when is_integer(index),
       do: eval_index_filter(left, -index, data, root)

  defp eval_filter(left, predicate, boolean?, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      items = Value.items(source)
      count = if boolean?, do: 0, else: length(items)

      case filter_predicate_items(items, predicate, root, count, 0, []) do
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

  defp eval_index_filter(left, index, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      keep_array? = is_struct(source, Value.Sequence) and source.keep_array
      {:ok, Value.sequence([Enum.at(Value.items(source), index, Value.undefined())], keep_array?)}
    end
  end

  defp eval_regular_path({:path, {:filter, left, predicate}, {:name, name}}, data, context) do
    eval_filtered_path(left, predicate, boolean_predicate?(predicate), name, data, context)
  end

  defp eval_regular_path(
         {:path, {:compiled_filter, left, predicate, boolean?}, {:name, name}},
         data,
         context
       ) do
    eval_filtered_path(left, predicate, boolean?, name, data, context)
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

  defp eval_filtered_path(left, {:literal, index}, _boolean?, name, data, context)
       when is_integer(index),
       do: eval_index_filtered_path(left, index, name, data, context)

  defp eval_filtered_path(left, {:negate, {:literal, index}}, _boolean?, name, data, context)
       when is_integer(index),
       do: eval_index_filtered_path(left, -index, name, data, context)

  defp eval_filtered_path(left, predicate, boolean?, name, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      items = Value.items(source)
      count = if boolean?, do: 0, else: length(items)
      keep_array? = is_struct(source, Value.Sequence) and source.keep_array

      case filter_path_items(items, predicate, context, count, name, 0, 0, []) do
        {:ok, selected, kept} ->
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

  defp eval_index_filtered_path(left, index, name, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      keep_array? = is_struct(source, Value.Sequence) and source.keep_array
      item = Enum.at(Value.items(source), index, Value.undefined())

      if Value.undefined?(item) do
        {:ok, Value.sequence([], keep_array?)}
      else
        selected = Semantics.select(item, name)
        values = if keep_array?, do: Value.items(selected), else: [selected]
        {:ok, Value.sequence(values, keep_array?)}
      end
    end
  end

  defp filter_predicate_items([], _predicate, _context, _count, _index, selected),
    do: {:ok, selected}

  defp filter_predicate_items([item | rest], predicate, context, count, index, selected) do
    case eval(predicate, item, context) do
      {:ok, result} ->
        next = if predicate_matches?(result, index, count), do: [item | selected], else: selected
        filter_predicate_items(rest, predicate, context, count, index + 1, next)

      error ->
        error
    end
  end

  defp filter_path_items([], _predicate, _context, _count, _name, _index, kept, selected),
    do: {:ok, selected, kept}

  defp filter_path_items([item | rest], predicate, context, count, name, index, kept, selected) do
    case eval(predicate, item, context) do
      {:ok, result} ->
        if predicate_matches?(result, index, count) do
          filter_path_items(
            rest,
            predicate,
            context,
            count,
            name,
            index + 1,
            kept + 1,
            [Semantics.select(item, name) | selected]
          )
        else
          filter_path_items(rest, predicate, context, count, name, index + 1, kept, selected)
        end

      error ->
        error
    end
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
      |> Enum.reduce_while({:ok, [], List.duplicate(nil, length(terms))}, fn item,
                                                                             {:ok, acc, types} ->
        case eval_sort_keys(terms, item, context) do
          {:ok, keys} ->
            case update_sort_types(keys, types) do
              {:ok, next_types} -> {:cont, {:ok, [{item, keys} | acc], next_types}}
              error -> {:halt, error}
            end

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, decorated, _types} ->
          decorated = Enum.reverse(decorated)
          sorted = sort_decorated(decorated, terms)
          {:ok, Value.sequence(Enum.map(sorted, &elem(&1, 0)))}

        error ->
          error
      end
    end
  end

  defp eval_indexed(
         {:index_bind, {:focus_bind, {:compiled_path, previous, step, _}, focus_name},
          index_name},
         data,
         context
       ),
       do: eval_focus_path(previous, step, focus_name, data, context, index_name)

  defp eval_indexed(
         {:index_bind, {:focus_bind, {:path, previous, step}, focus_name}, index_name},
         data,
         context
       ),
       do: eval_focus_path(previous, step, focus_name, data, context, index_name)

  defp eval_indexed({:index_bind, {:compiled_path, previous, step, _}, name}, data, context),
    do: eval_indexed_step(previous, step, name, data, context)

  defp eval_indexed({:index_bind, left, name}, data, context) do
    with {:ok, frames} <- eval_indexed(left, data, context) do
      {:ok, IndexBindings.bind_frames(frames, name)}
    end
  end

  defp eval_indexed({:focus_bind, {:compiled_path, previous, step, _}, name}, data, context),
    do: eval_focus_path(previous, step, name, data, context)

  defp eval_indexed({:focus_bind, {:path, previous, step}, name}, data, context),
    do: eval_focus_path(previous, step, name, data, context)

  defp eval_indexed({:focus_bind, {:name, _} = step, name}, data, context),
    do: eval_focus_path(nil, step, name, data, context)

  defp eval_indexed({:focus_bind, left, name}, data, context) do
    with {:ok, frames} <- eval_indexed(left, data, context),
         do: {:ok, Enum.map(frames, fn {item, env} -> {item, Map.put(env, name, item)} end)}
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
      Enum.reduce_while(frames, {:ok, [], List.duplicate(nil, length(terms))}, fn
        {item, environment} = frame, {:ok, acc, types} ->
          case eval_sort_keys(terms, item, %{context | environment: environment}) do
            {:ok, keys} ->
              case update_sort_types(keys, types) do
                {:ok, next_types} -> {:cont, {:ok, [{frame, keys} | acc], next_types}}
                error -> {:halt, error}
              end

            error ->
              {:halt, error}
          end
      end)
      |> case do
        {:ok, decorated, _types} ->
          decorated = Enum.reverse(decorated)

          {:ok,
           decorated
           |> sort_decorated(terms)
           |> Enum.map(&elem(&1, 0))}

        error ->
          error
      end
    end
  end

  defp eval_indexed({:filter, left, predicate}, data, context),
    do: eval_indexed_filter(left, predicate, boolean_predicate?(predicate), data, context)

  defp eval_indexed({:compiled_filter, left, predicate, boolean?}, data, context),
    do: eval_indexed_filter(left, predicate, boolean?, data, context)

  defp eval_indexed({:keep_array, ast}, data, context), do: eval_indexed(ast, data, context)
  defp eval_indexed({:block, [ast]}, data, context), do: eval_indexed(ast, data, context)

  defp eval_indexed(:parent, _data, context) do
    case Ancestry.pop(context.environment) do
      {:ok, parent, environment} -> {:ok, [{parent, environment}]}
      :error -> {:error, Error.new("S0217", "No parent context is available")}
    end
  end

  defp eval_indexed({:name, name}, data, context) do
    selected = Semantics.select(data, name)

    environment =
      if Map.get(context, :parent_mode, false),
        do: Ancestry.push(context.environment, data),
        else: context.environment

    {:ok, Enum.map(Value.items(selected), &{&1, environment})}
  end

  defp eval_indexed(ast, data, context) do
    with {:ok, value} <- eval(ast, data, context),
         do: {:ok, Enum.map(Value.items(value), &{&1, context.environment})}
  end

  defp eval_focus_path(previous, step, name, data, context, index_name \\ nil),
    do:
      IndexBindings.expand(
        :focus,
        previous,
        step,
        name,
        index_name,
        data,
        context,
        &eval_indexed/3,
        &eval/3
      )

  defp eval_indexed_step(previous, step, name, data, context),
    do:
      IndexBindings.expand(
        :index,
        previous,
        step,
        name,
        nil,
        data,
        context,
        &eval_indexed/3,
        &eval/3
      )

  defp eval_indexed_filter(left, predicate, boolean?, data, context),
    do: IndexBindings.filter(left, predicate, boolean?, data, context, &eval_indexed/3, &eval/3)

  defp eval_indexed_path(left, right, data, context),
    do: IndexBindings.path(left, right, data, context, &eval_indexed/3, &eval/3)

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

  defp higher_order(name, values, data),
    do: HigherOrder.call(name, values, data, &invoke/3)

  defp invoke_callback(callback, values, data),
    do: HigherOrder.invoke_callback(callback, values, data, &invoke/3)

  defp invoke_or_partial(function, values, data) do
    invoke_or_partial(function, values, data, placeholder_args?(values))
  end

  defp invoke_or_partial(function, values, data, partial?) do
    if partial? do
      {:ok, %Partial{function: function, arguments: values}}
    else
      invoke(function, values, data)
    end
  end

  defp placeholder_args?([%Placeholder{} | _]), do: true
  defp placeholder_args?([_ | rest]), do: placeholder_args?(rest)
  defp placeholder_args?([]), do: false

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
    do: ast |> AST.children() |> Enum.reduce(acc, &referenced_variables/2)

  defp referenced_variables(ast, acc) when is_list(ast),
    do: Enum.reduce(ast, acc, &referenced_variables/2)

  defp referenced_variables(_, acc), do: acc

  defp invoke(%Closure{leaf?: true} = closure, values, data) do
    state = Process.get({__MODULE__, :closure_depth_state})
    {depth, max_depth} = if state == nil, do: {0, 1024}, else: state

    if depth >= max_depth,
      do: {:error, Error.new("U1001", "Function recursion limit exceeded")},
      else: invoke_closure_loop(closure, values, data, 0)
  end

  defp invoke(%Closure{} = closure, values, data) do
    key = {__MODULE__, :closure_depth_state}
    prior = Process.get(key)
    {depth, max_depth} = if prior == nil, do: {0, 1024}, else: prior

    if depth >= max_depth do
      {:error, Error.new("U1001", "Function recursion limit exceeded")}
    else
      Process.put(key, {depth + 1, max_depth})

      try do
        invoke_closure_loop(closure, values, data, 0)
      after
        if prior == nil, do: Process.delete(key), else: Process.put(key, prior)
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

  defp invoke(%Transform{} = transform, [input], _data),
    do: Transforms.apply(transform, input, &eval/3, &predicate_matches?/3)

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
    case LimitedRegex.run(pattern, value, return: :index) do
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
    case bind_closure_values(closure, values, data) do
      {:ok, bound} ->
        environment = bind_closure_environment(closure.environment, parameters, bound)
        context = %{root: closure.root, environment: environment}

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

  defp bind_closure_values(%Closure{signature: nil, arity: 0}, [], _data), do: {:ok, []}

  defp bind_closure_values(%Closure{signature: nil, arity: 1}, [_] = values, _data),
    do: {:ok, values}

  defp bind_closure_values(%Closure{signature: nil, arity: 2}, [_, _] = values, _data),
    do: {:ok, values}

  defp bind_closure_values(%Closure{signature: nil, arity: 3}, [_, _, _] = values, _data),
    do: {:ok, values}

  defp bind_closure_values(closure, values, data),
    do: Signature.bind(closure.signature, closure.parameters, values, data)

  defp bind_closure_environment(environment, [], []), do: environment

  defp bind_closure_environment(environment, [name], [value]),
    do: Map.put(environment, name, value)

  defp bind_closure_environment(environment, [a, b], [first, second]),
    do: environment |> Map.put(a, first) |> Map.put(b, second)

  defp bind_closure_environment(environment, [a, b, c], [first, second, third]),
    do: environment |> Map.put(a, first) |> Map.put(b, second) |> Map.put(c, third)

  defp bind_closure_environment(environment, parameters, values),
    do: Map.merge(environment, bind_parameters(parameters, values))

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
    if LimitedRegex.match?(pattern, "") do
      {:error, Error.new("D1004", "Regex must not match an empty string")}
    else
      matches = LimitedRegex.scan(pattern, value, return: :index)
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
    values = select_each_items(items, name, flatten_arrays?, [])
    {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
  end

  defp eval_each(items, {:variable, _} = ast, context, _flatten_arrays?, keep_array?) do
    case eval_each_items(items, ast, context, [], true) do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
      error -> error
    end
  end

  defp eval_each(items, ast, root, _flatten_arrays?, keep_array?) do
    case eval_each_items(items, ast, root, [], false) do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
      error -> error
    end
  end

  defp select_each_items([], _name, _flatten?, values), do: values

  defp select_each_items([item | rest], name, flatten?, values) do
    selected = Semantics.select(item, name)
    next = if flatten?, do: Enum.reverse(Value.items(selected), values), else: [selected | values]
    select_each_items(rest, name, flatten?, next)
  end

  defp eval_each_items([], _ast, _context, values, _skip_empty?), do: {:ok, values}

  defp eval_each_items([item | rest], ast, context, values, skip_empty?) do
    case eval(ast, item, context) do
      {:ok, []} when skip_empty? -> eval_each_items(rest, ast, context, values, skip_empty?)
      {:ok, value} -> eval_each_items(rest, ast, context, [value | values], skip_empty?)
      error -> error
    end
  end

  defp eval_array_items([], _data, _context, acc), do: {:ok, Enum.reverse(acc)}

  defp eval_array_items([expression | rest], data, context, acc) do
    case eval(expression, data, context) do
      {:ok, value} ->
        eval_array_items(rest, data, context, append_array_item(expression, value, acc))

      error ->
        error
    end
  end

  defp append_array_item({:array, _}, value, acc), do: [value | acc]
  defp append_array_item({:constant_array, _}, value, acc), do: [value | acc]
  defp append_array_item(_, %Value.Sequence{items: items}, acc), do: Enum.reverse(items, acc)
  defp append_array_item(_, value, acc) when is_list(value), do: Enum.reverse(value, acc)
  defp append_array_item(_, %Value.Undefined{}, acc), do: acc
  defp append_array_item(_, value, acc), do: [value | acc]

  defp eval_list([], _data, _root), do: {:ok, []}

  defp eval_list([node], data, root) do
    with {:ok, value} <- eval(node, data, root), do: {:ok, [value]}
  end

  defp eval_list([first, second], data, root) do
    with {:ok, a} <- eval(first, data, root),
         {:ok, b} <- eval(second, data, root),
         do: {:ok, [a, b]}
  end

  defp eval_list([first, second, third], data, root) do
    with {:ok, a} <- eval(first, data, root),
         {:ok, b} <- eval(second, data, root),
         {:ok, c} <- eval(third, data, root),
         do: {:ok, [a, b, c]}
  end

  defp eval_list(nodes, data, root) do
    eval_list_many(nodes, data, root, [])
  end

  defp eval_list_many([], _data, _context, values), do: {:ok, Enum.reverse(values)}

  defp eval_list_many([node | rest], data, context, values) do
    case eval(node, data, context) do
      {:ok, value} -> eval_list_many(rest, data, context, [value | values])
      error -> error
    end
  end

  defp eval_boolean(ast, data, root) do
    with {:ok, value} <- eval(ast, data, root), do: {:ok, Semantics.boolean(value)}
  end

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

  defp sort_decorated(decorated, [{:asc, _}]) do
    decorated
    |> Enum.map(fn {_, [{_, value}]} = row ->
      key = if Value.undefined?(value), do: {1, nil}, else: {0, value}
      {key, row}
    end)
    |> then(&:lists.keysort(1, &1))
    |> Enum.map(&elem(&1, 1))
  end

  defp sort_decorated(decorated, _terms),
    do: Enum.sort(decorated, fn {_, a}, {_, b} -> compare_sort_keys(a, b) end)

  defp update_sort_types([], []), do: {:ok, []}

  defp update_sort_types([{_, %Value.Undefined{}} | keys], [type | types]) do
    with {:ok, next} <- update_sort_types(keys, types), do: {:ok, [type | next]}
  end

  defp update_sort_types([{_, value} | keys], [type | types]) do
    next_type = if is_number(value), do: :number, else: :string

    if type == nil or type == next_type do
      with {:ok, next} <- update_sort_types(keys, types), do: {:ok, [next_type | next]}
    else
      {:error, Error.new("T2007", "Sort keys have incompatible types")}
    end
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
