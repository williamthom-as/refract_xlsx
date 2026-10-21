defmodule Refract.E2E.MixedFolderTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.Classify
  alias Refract.Classify.Result
  alias Refract.CSV
  alias Refract.Shape
  alias Refract.Table
  alias Refract.XLSX

  defp shapes do
    [
      Shape.new(
        name: "invoice",
        spec:
          Table.spec(
            header: [columns: %{"sku" => ["sku"], "item" => ["item"], "total" => ["total"]}],
            row: [match: %{"sku" => :integer, "total" => :number}]
          )
      ),
      Shape.new(
        name: "aws_bill",
        spec:
          Table.spec(
            header: [columns: %{"account" => ["account"], "cost" => ["cost"]}],
            row: [match: %{"account" => ~r/^\d{12}$/, "cost" => :number}]
          )
      )
    ]
  end

  defp invoices,
    do: [
      %{"sku" => 78_632_478, "item" => "apple", "total" => Decimal.new("3")},
      %{"sku" => 12_319_082, "item" => "pear", "total" => Decimal.new("9.5")}
    ]

  defp bills, do: [%{"account" => 123_456_789_012, "cost" => Decimal.new("1.25")}]

  test "csv and xlsx files classify against one shape set", %{tmp_dir: dir} do
    :ok = CSV.write(invoices(), Path.join(dir, "invoice.csv"), header: ["sku", "item", "total"])
    :ok = XLSX.write(invoices(), Path.join(dir, "invoice.xlsx"), header: ["sku", "item", "total"])
    :ok = CSV.write(bills(), Path.join(dir, "aws_bill.csv"), header: ["account", "cost"])

    :ok =
      XLSX.write(bills(), Path.join(dir, "aws_bill.xlsx"),
        header: ["account", "cost"],
        sheet: "Bill"
      )

    {:ok, results} = Classify.folder(dir, shapes(), readers: [XLSX, CSV])

    assert results
           |> Enum.map(fn {path, {:ok, %Result{verdict: verdict, shape: shape}}} ->
             {Path.basename(path), verdict, shape.name}
           end) == [
             {"aws_bill.csv", :match, "aws_bill"},
             {"aws_bill.xlsx", :match, "aws_bill"},
             {"invoice.csv", :match, "invoice"},
             {"invoice.xlsx", :match, "invoice"}
           ]
  end

  test "an xlsx result names its sheet, a csv result does not", %{tmp_dir: dir} do
    :ok =
      XLSX.write(bills(), Path.join(dir, "aws_bill.xlsx"),
        header: ["account", "cost"],
        sheet: "Bill"
      )

    :ok = CSV.write(bills(), Path.join(dir, "aws_bill.csv"), header: ["account", "cost"])

    {:ok, results} = Classify.folder(dir, shapes(), readers: [XLSX, CSV])

    assert [{_csv, {:ok, csv}}, {_xlsx, {:ok, xlsx}}] = Enum.to_list(results)
    refute Map.has_key?(csv.file.format, :sheet)
    assert xlsx.file.format.sheet == "Bill"
  end
end
