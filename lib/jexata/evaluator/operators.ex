defmodule Jexata.Evaluator.Operators do
  @moduledoc false
  alias Jexata.{Error, Semantics}
  alias Jexata.Runtime.Value

  def binary("<", a, b) when is_number(a) and is_number(b), do: {:ok, a < b}
  def binary("<=", a, b) when is_number(a) and is_number(b), do: {:ok, a <= b}
  def binary(">", a, b) when is_number(a) and is_number(b), do: {:ok, a > b}
  def binary(">=", a, b) when is_number(a) and is_number(b), do: {:ok, a >= b}

  def binary("=", a, b)
      when not is_struct(a, Value.Undefined) and not is_struct(b, Value.Undefined),
      do: {:ok, a == b}

  def binary("!=", a, b)
      when not is_struct(a, Value.Undefined) and not is_struct(b, Value.Undefined),
      do: {:ok, a != b}

  def binary("+", a, b)
      when is_integer(a) and is_integer(b) and abs(a) <= 9_007_199_254_740_991 and
             abs(b) <= 9_007_199_254_740_991,
      do: {:ok, number_result(a + b)}

  def binary("-", a, b)
      when is_integer(a) and is_integer(b) and abs(a) <= 9_007_199_254_740_991 and
             abs(b) <= 9_007_199_254_740_991,
      do: {:ok, number_result(a - b)}

  def binary("*", a, b)
      when is_integer(a) and is_integer(b) and abs(a) <= 9_007_199_254_740_991 and
             abs(b) <= 9_007_199_254_740_991,
      do: {:ok, number_result(a * b)}

  def binary("%", a, b)
      when is_integer(a) and is_integer(b) and b != 0 and
             abs(a) <= 9_007_199_254_740_991 and abs(b) <= 9_007_199_254_740_991,
      do: {:ok, number_result(rem(a, b))}

  def binary("/", a, b) when is_number(a) and is_number(b) and b == 0,
    do: {:error, Error.new("D1001", "Division by zero")}

  def binary("/", a, b) when is_number(a) and is_number(b) do
    {:ok, a / b}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  def binary("+", a, b) when is_number(a) and is_number(b) do
    {:ok, number_result(a + b)}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  def binary("-", a, b) when is_number(a) and is_number(b) do
    {:ok, number_result(a - b)}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  def binary("*", a, b) when is_number(a) and is_number(b) do
    {:ok, number_result(a * b)}
  rescue
    ArithmeticError -> {:error, Error.new("D1001", "Numeric result is not finite")}
  end

  def binary(op, a, b) when op in ["<", "<=", ">", ">="] do
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

  def binary(op, a, b) when op in ["+", "-", "*", "/", "%"] do
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

  def binary("&", a, b), do: {:ok, string(a) <> string(b)}

  def binary("..", a, b) do
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

  def binary("in", a, b), do: {:ok, Semantics.compare("in", a, b)}

  def binary(op, a, b)
      when op in ["=", "!="] and
             (is_struct(a, Value.Undefined) or is_struct(b, Value.Undefined)),
      do: {:ok, false}

  def binary(_, a, b) when is_struct(a, Value.Undefined) or is_struct(b, Value.Undefined),
    do: {:ok, Value.undefined()}

  def binary(op, a, b) when op in ["=", "!=", "in"], do: {:ok, Semantics.compare(op, a, b)}

  def binary(op, _, _), do: {:error, Error.new("T1007", "Unsupported operator #{op}")}

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
end
