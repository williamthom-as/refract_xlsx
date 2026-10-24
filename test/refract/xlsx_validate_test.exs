defmodule Refract.XLSXValidateTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.Shape
  alias Refract.Table
  alias Refract.XLSX

  defp order do
    Shape.new(
      name: "order",
      spec:
        Table.spec(
          header: [columns: %{"item" => ["item"], "units" => ["units"], "total" => ["total"]}],
          row: [match: %{"units" => :integer, "total" => :number}]
        ),
      validation: [
        columns: %{"units" => [{:min, 1}], "total" => [:required, {:max, 10_000}]},
        rows: [{:has_item, &(&1["item"] not in [nil, ""])}]
      ]
    )
  end

  defp workbook!(rows, dir) do
    path = Path.join(dir, "order.xlsx")
    :ok = XLSX.write(rows, path, header: ["item", "units", "total"], sheet: "Order")

    path
  end

  test "typed cells are validated, issues name the sheet line", %{tmp_dir: dir} do
    path =
      workbook!(
        [
          %{"item" => "stapler", "units" => 4, "total" => Decimal.new("33.00")},
          %{"item" => "press", "units" => 1, "total" => Decimal.new("12500.00")},
          %{"item" => "", "units" => 0, "total" => Decimal.new("5.00")}
        ],
        dir
      )

    assert {:ok, result} = XLSX.validate(path, order(), sheet: "Order")

    refute result.valid
    assert result.rows == 3

    assert [
             %{line: 3, column: "total", rule: {:max, 10_000}},
             %{line: 4, column: "units", rule: {:min, 1}},
             %{line: 4, column: nil, rule: :has_item}
           ] = result.issues
  end

  test "a workbook whose content passes is valid", %{tmp_dir: dir} do
    path = workbook!([%{"item" => "paper", "units" => 10, "total" => Decimal.new("54.00")}], dir)

    assert {:ok, %{valid: true, rows: 1, issues: []}} = XLSX.validate(path, order())
  end
end
