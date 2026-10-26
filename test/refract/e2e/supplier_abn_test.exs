defmodule Refract.E2E.SupplierAbnTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.Shape
  alias Refract.Table
  alias Refract.XLSX
  alias Refract.XLSX.TestValidators.ABN

  defp invoice do
    Shape.new(
      name: "acme_invoice",
      spec:
        Table.spec(
          header: [columns: %{"sku" => ["sku"], "qty" => ["qty"], "line_total" => ["line total"]}],
          stop: [:blank]
        ),
      validation: [columns: %{"line_total" => [:required, {:max, 10_000}]}],
      fields: %{"supplier_abn" => [label: "abn", rules: [:required, ABN]]}
    )
  end

  defp invoice!(abn, dir) do
    path = Path.join(dir, "acme_invoice.xlsx")

    rows = [
      ["ACME PTY LTD - Tax Invoice", nil, nil],
      ["Invoice No", "INV-1001", nil],
      ["ABN", abn, nil],
      ["SKU", "Qty", "Line Total"],
      ["A-100", 3, Decimal.new("37.50")],
      ["B-200", 1, Decimal.new("99.00")]
    ]

    "refract"
    |> Exceed.Workbook.new()
    |> Exceed.Workbook.add_worksheet(Exceed.Worksheet.new("Invoice", nil, rows))
    |> Exceed.stream!()
    |> Stream.into(File.stream!(path))
    |> Stream.run()

    path
  end

  test "a valid supplier abn passes", %{tmp_dir: dir} do
    assert {:ok, %{valid: true, rows: 2}} =
             XLSX.validate(invoice!("51 824 753 556", dir), invoice())
  end

  test "a bad checksum is an issue naming the field and the validator", %{tmp_dir: dir} do
    assert {:ok, %{valid: false, issues: [issue]}} =
             XLSX.validate(invoice!("51 824 753 557", dir), invoice())

    assert %{field: "supplier_abn", line: 3, rule: ABN, column: nil} = issue
  end

  test "an abn typed as a number is checked by its digits", %{tmp_dir: dir} do
    assert {:ok, %{valid: true, fields: %{"supplier_abn" => abn}}} =
             XLSX.validate(invoice!(51_824_753_556, dir), invoice())

    refute is_binary(abn)

    assert {:ok, %{valid: false, issues: [%{field: "supplier_abn", rule: ABN}]}} =
             XLSX.validate(invoice!(51_824_753_557, dir), invoice())
  end
end
