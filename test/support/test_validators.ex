defmodule Refract.XLSX.TestValidators.ABN do
  @behaviour Refract.Validate.Validator

  @weights [10, 1, 3, 5, 7, 9, 11, 13, 15, 17, 19]

  @impl Refract.Validate.Validator
  def valid?(cell, _opts) do
    digits =
      cell
      |> to_string()
      |> Refract.Clean.digits()
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)

    length(digits) == 11 and checksum(digits) == 0
  end

  defp checksum([first | rest]) do
    [first - 1 | rest]
    |> Enum.zip(@weights)
    |> Enum.map(fn {digit, weight} -> digit * weight end)
    |> Enum.sum()
    |> rem(89)
  end
end
