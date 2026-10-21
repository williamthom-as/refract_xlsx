defmodule Refract.E2E.XLSXComplexJoinsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.CSV
  alias Refract.Grid
  alias Refract.Query
  alias Refract.Table
  alias Refract.XLSX

  @fixtures Path.expand("../../fixtures", __DIR__)

  defp located(grid, columns) do
    {:ok, table} = Grid.locate(grid, Table.spec(header: [columns: Map.new(columns, &{&1, [&1]})]))

    table
  end

  test "two sheets of offset tables load from grids and join with their totals", %{tmp_dir: dir} do
    {:ok, names} = XLSX.load(Path.join(@fixtures, "offset.xlsx"), sheet: "names")
    {:ok, ages} = XLSX.load(Path.join(@fixtures, "offset.xlsx"), sheet: "ages")

    query = Query.open!(engine: Refract.Query.DuckDB)

    :ok = Query.table(query, "names", located(names, ["id", "first_name", "last_name"]))
    :ok = Query.table(query, "ages", located(ages, ["id", "age", "color"]))

    result =
      Query.run!(
        query,
        """
        SELECT id, n.first_name, n.last_name, a.color, a.age,
               $1::VARCHAR AS names_total, $2::VARCHAR AS ages_total
        FROM names n JOIN ages a USING (id)
        ORDER BY id
        """,
        [
          names |> Grid.value(label: "total") |> to_string(),
          ages |> Grid.value(label: "total") |> to_string()
        ]
      )

    out = Path.join(dir, "joined.csv")
    :ok = CSV.write(result.rows, out, header: result.columns)

    assert File.read!(out) ==
             File.read!(Path.join(@fixtures, "golden/complex_joins/expected.csv"))
  end
end
