defmodule Refract.XLSX do
  @moduledoc """
  xlsx reader for refract, built on `xlsx_reader`. reads one sheet at a time, cells come back as
  native values: text, `Decimal` numbers, `Date`, `NaiveDateTime`, `Time`, booleans, `""` for blanks.

      {:ok, rows} = Refract.XLSX.stream("bills.xlsx", sheet: "Sep")
      {:ok, result} = Refract.XLSX.classify("bills.xlsx", shapes, sheet: 2)
  """

  use Refract.Reader

  @type sheet :: String.t() | pos_integer()

  @type open_opt :: {:sheet, sheet() | nil} | {:hidden, boolean()}

  @spec extensions() :: [String.t()]

  @impl Refract.Reader
  def extensions, do: ["xlsx", "xlsm"]

  @spec open(Refract.source(), [open_opt()]) :: {:ok, Enumerable.t()} | {:error, term()}

  @impl Refract.Reader
  def open(source, opts) do
    opts = Keyword.validate!(opts, sheet: nil, hidden: false)
    sheet = Keyword.fetch!(opts, :sheet)
    hidden = Keyword.fetch!(opts, :hidden)

    validate_sheet(sheet)
    validate_hidden(hidden)

    with {:ok, workbook} <- workbook(source),
         {:ok, name} <- sheet_name(workbook, sheet, hidden),
         {:ok, rows} <-
           XlsxReader.sheet(workbook.package, name, number_type: Decimal, blank_value: "") do
      {:ok, Enum.map(rows, &cells(&1, workbook.package.workbook.base_date))}
    end
  end

  @spec facts(Refract.source(), [open_opt()]) :: {:ok, map()} | {:error, term()}

  @impl Refract.Reader
  def facts(source, opts) do
    opts = Keyword.validate!(opts, sheet: nil, hidden: false)
    sheet = Keyword.fetch!(opts, :sheet)
    hidden = Keyword.fetch!(opts, :hidden)

    validate_sheet(sheet)
    validate_hidden(hidden)

    with {:ok, workbook} <- workbook(source),
         {:ok, name} <- sheet_name(workbook, sheet, hidden) do
      {:ok, %{sheet: name, sheets: workbook.visible, hidden: workbook.all -- workbook.visible}}
    end
  end

  defp validate_sheet(nil), do: :ok
  defp validate_sheet(sheet) when is_binary(sheet), do: :ok
  defp validate_sheet(sheet) when is_integer(sheet) and sheet > 0, do: :ok

  defp validate_sheet(sheet) do
    raise ArgumentError, "sheet must be a name or a position from 1, got: #{inspect(sheet)}"
  end

  defp validate_hidden(hidden) when is_boolean(hidden), do: :ok

  defp validate_hidden(hidden) do
    raise ArgumentError, "hidden must be true or false, got: #{inspect(hidden)}"
  end

  defp workbook(source) do
    with {:ok, package} <- package(source, false),
         {:ok, visible} <- package(source, true) do
      {:ok,
       %{
         package: package,
         all: XlsxReader.sheet_names(package),
         visible: XlsxReader.sheet_names(visible)
       }}
    end
  end

  defp package(path, exclude_hidden) when is_binary(path),
    do: path |> XlsxReader.open(package_opts(exclude_hidden)) |> opened()

  defp package({:string, content}, exclude_hidden),
    do: content |> XlsxReader.open([source: :binary] ++ package_opts(exclude_hidden)) |> opened()

  defp package({:stream, chunks}, exclude_hidden),
    do: package({:string, chunks |> Enum.to_list() |> IO.iodata_to_binary()}, exclude_hidden)

  defp package(source, _exclude_hidden), do: {:error, {:unsupported_source, source}}

  defp package_opts(exclude_hidden),
    do: [exclude_hidden_sheets?: exclude_hidden, supported_custom_formats: formats()]

  defp opened({:ok, package}), do: {:ok, package}
  defp opened({:error, "file not found"}), do: {:error, :enoent}
  defp opened({:error, message}), do: {:error, {:invalid_xlsx, message}}

  defp sheet_name(workbook, nil, hidden), do: workbook |> candidates(hidden) |> first_sheet()

  defp sheet_name(%{all: all}, name, _hidden) when is_binary(name) do
    if name in all, do: {:ok, name}, else: {:error, {:unknown_sheet, name}}
  end

  defp sheet_name(workbook, position, hidden) do
    workbook
    |> candidates(hidden)
    |> Enum.at(position - 1)
    |> found(position)
  end

  defp candidates(%{all: all}, true), do: all
  defp candidates(%{visible: visible}, false), do: visible

  defp first_sheet([name | _names]), do: {:ok, name}
  defp first_sheet([]), do: {:error, :no_sheets}

  defp found(nil, position), do: {:error, {:unknown_sheet, position}}
  defp found(name, _position), do: {:ok, name}

  defp cells(row, base_date), do: Enum.map(row, &cell(&1, base_date))

  defp cell(%NaiveDateTime{} = value, base_date) do
    if NaiveDateTime.to_date(value) == base_date, do: NaiveDateTime.to_time(value), else: value
  end

  defp cell(value, _base_date), do: value

  defp formats do
    locale = "(\\[\\$-[0-9A-Fa-f]+\\])?"
    meridiem = "(am\\/pm|a\\/p)?"

    [
      {Regex.compile!(
         "\\A#{locale}(?=.*[yd])(?=.*[hs])[ymdhs\\\\\\/\\-\\.\\s,:0]+#{meridiem}\\z",
         "i"
       ), :date_time},
      {Regex.compile!("\\A#{locale}(?=.*[yd])[ymd\\\\\\/\\-\\.\\s,]+\\z", "i"), :date},
      {Regex.compile!("\\A#{locale}(?=.*[hs])[hms\\\\\\.\\s:0]+#{meridiem}\\z", "i"), :time}
    ]
  end
end
