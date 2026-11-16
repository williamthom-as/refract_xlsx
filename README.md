# refract_xlsx

XLSX reader and writer for [refract](https://github.com/williamthom-as/refract_core).

- `Refract.XLSX` reads `.xlsx` / `.xlsm` one sheet at a time (`sheet:` a name or a position from 1, default the first visible sheet; `hidden: true` counts hidden sheets)
- cells come back typed: text, `Decimal` numbers, `Date`, `NaiveDateTime`, `Time`, booleans, `""` for blanks, formula values
- writes one sheet per file (`sheet:`, default `"Sheet1"`), values keep their types, times as text
- `facts/2` names the sheet read, the visible sheets and the hidden ones
- a workbook with several tables: `Refract.XLSX.sheets/2`, `Refract.XLSX.classify_sheets/3`
- built on `xlsx_reader` and `exceed`; the old binary `.xls` is not supported

```elixir
{:ok, rows} = Refract.XLSX.stream("bills.xlsx", sheet: "Sep")
{:ok, results} = Refract.Classify.folder("inbox", shapes, readers: [Refract.XLSX, Refract.CSV])

{:ok, sheets} = Refract.XLSX.classify_sheets("q3.xlsx", shapes)
:ok = Refract.XLSX.write(rows, "out/report.xlsx", header: ["account", "cost"], sheet: "Report")
```

## Install

```elixir
{:refract_xlsx, github: "williamthom-as/refract_xlsx", tag: "v0.1.0"}
```

## Development

against local checkouts: `REFRACT_PATH=../refract REFRACT_DUCKDB_PATH=../refract_duckdb mix test`

## License

Apache-2.0, see [LICENSE](LICENSE).
