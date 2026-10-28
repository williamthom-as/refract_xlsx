defmodule Refract.XLSXProfileTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 20_000

  alias Refract.Profile
  alias Refract.Profile.Cluster
  alias Refract.Profile.Column
  alias Refract.Profile.Variant
  alias Refract.Shape
  alias Refract.Table
  alias Refract.XLSX

  defp ledger do
    Shape.new(
      name: "ledger",
      spec:
        Table.spec(
          header: [columns: %{"account" => ["account"], "cost_centre" => ["cost centre"]}]
        )
    )
  end

  defp workbook!(dir, name, cost_centres, opts \\ []) do
    path = Path.join(dir, name)
    rows = Enum.map(cost_centres, &%{"account" => "A-1", "cost centre" => &1})
    :ok = XLSX.write(rows, path, Keyword.merge([header: ["account", "cost centre"]], opts))

    path
  end

  test "spellings group with their sheet rows", %{tmp_dir: dir} do
    path = workbook!(dir, "ledger.xlsx", ["Cost Center 1", "costcenter1", "Cost Center 1"])

    assert {:ok, %{columns: %{"cost_centre" => column}}} = XLSX.profile(path, ledger())

    assert %Column{
             clusters: [
               %Cluster{
                 most_common: "Cost Center 1",
                 variants: [
                   %Variant{value: "Cost Center 1", count: 2, lines: [2, 4]},
                   %Variant{value: "costcenter1", count: 1, lines: [3]}
                 ]
               }
             ]
           } = column
  end

  test "a number and the same number stored as text group", %{tmp_dir: dir} do
    path = workbook!(dir, "codes.xlsx", [12, "12"])

    assert {:ok, %{columns: %{"cost_centre" => %Column{clusters: [cluster]}}}} =
             XLSX.profile(path, ledger())

    assert Enum.map(cluster.variants, & &1.value) == [Decimal.new("12"), "12"]
  end

  test "sheet picks the sheet to profile", %{tmp_dir: dir} do
    path = workbook!(dir, "ledger.xlsx", ["north", "North"], sheet: "Ledger")

    assert {:ok, %{rows: 2, columns: %{"cost_centre" => %Column{clusters: [_cluster]}}}} =
             XLSX.profile(path, ledger(), sheet: "Ledger")
  end

  test "a folder of workbooks profiles as one, lines by file", %{tmp_dir: dir} do
    jan = workbook!(dir, "1_jan.xlsx", ["north"])
    feb = workbook!(dir, "2_feb.xlsx", ["North"])

    assert {:ok, %{results: %{{"ledger", 1} => result}, skipped: []}} =
             Profile.folder(dir, [ledger()], readers: [XLSX])

    assert %{columns: %{"cost_centre" => %Column{clusters: [%Cluster{variants: variants}]}}} =
             result

    assert Enum.map(variants, & &1.files) == [%{jan => [2]}, %{feb => [2]}]
  end
end
