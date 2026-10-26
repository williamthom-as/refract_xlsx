defmodule Refract.E2E.InvoiceTotalsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.Parse
  alias Refract.Shape
  alias Refract.Table
  alias Refract.XLSX

  defp invoice do
    Shape.new(
      name: "acme_invoice",
      spec:
        Table.spec(
          header: [columns: %{"sku" => ["sku"], "qty" => ["qty"], "line_total" => ["line total"]}],
          stop: [:blank]
        ),
      validation: [
        columns: %{"line_total" => [:required, {:max, 10_000}]},
        document: [{:total_matches_lines, &total_matches_lines?/1}]
      ],
      fields: %{"total" => [label: "total", rules: [:required, :number]]}
    )
  end

  defp total_matches_lines?(%{fields: %{"total" => total}, rows: rows}) do
    rows
    |> Enum.map(&Parse.number!(&1["line_total"]))
    |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
    |> Decimal.eq?(Parse.number!(total))
  end

  defp invoice!(dir, total) do
    path = Path.join(dir, "acme_invoice.xlsx")

    rows = [
      ["ACME PTY LTD - Tax Invoice", nil, nil],
      ["Invoice No", "INV-1001", nil],
      [nil, nil, nil],
      ["SKU", "Qty", "Line Total"],
      ["A-100", 3, Decimal.new("37.50")],
      ["B-200", 1, Decimal.new("99.00")],
      [nil, nil, nil],
      ["Total", nil, total]
    ]

    "refract"
    |> Exceed.Workbook.new()
    |> Exceed.Workbook.add_worksheet(Exceed.Worksheet.new("Invoice", nil, rows))
    |> Exceed.stream!()
    |> Stream.into(File.stream!(path))
    |> Stream.run()

    path
  end

  test "a typed total matching its typed lines is valid", %{tmp_dir: dir} do
    assert {:ok, %{valid: true, rows: 2, fields: %{"total" => total}}} =
             XLSX.validate(invoice!(dir, Decimal.new("136.50")), invoice())

    refute is_binary(total)
  end

  test "a total that does not match its lines fails the document rule", %{tmp_dir: dir} do
    assert {:ok, %{valid: false, issues: [issue]}} =
             XLSX.validate(invoice!(dir, Decimal.new("150.00")), invoice())

    assert %{rule: :total_matches_lines, line: nil, column: nil, field: nil} = issue
  end

  test "a total typed as text is read the same way", %{tmp_dir: dir} do
    assert {:ok, %{valid: true}} = XLSX.validate(invoice!(dir, "136.50"), invoice())
  end
end
