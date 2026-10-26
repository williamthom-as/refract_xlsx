defmodule Refract.XLSX do
  @moduledoc """
  xlsx reader and writer for refract, built on `xlsx_reader` and `exceed`.
  reads one sheet at a time, cells come back as native values: text, `Decimal` numbers, `Date`,
  `NaiveDateTime`, `Time`, booleans, `""` for blanks. writes native values with their types,
  times as text.

      {:ok, rows} = Refract.XLSX.stream("bills.xlsx", sheet: "Sep")
      {:ok, result} = Refract.XLSX.classify("bills.xlsx", shapes, sheet: 2)
      {:ok, [{"Jul", {:ok, result}} | _sheets]} = Refract.XLSX.classify_sheets("q3.xlsx", shapes)
      :ok = Refract.XLSX.write(rows, "out/report.xlsx", header: ["account", "cost"], sheet: "Report")
  """

  use Refract.Reader
  use Refract.Writer

  @type sheet :: String.t() | pos_integer()

  @type open_opt :: {:sheet, sheet() | nil} | {:hidden, boolean()}

  @type encode_opt :: {:header, [String.t()] | nil} | {:sheet, String.t()}

  @spec extension() :: String.t()

  @impl Refract.Writer
  def extension, do: "xlsx"

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

  @spec sheets(Refract.source(), [open_opt()]) :: {:ok, [String.t()]} | {:error, term()}

  def sheets(source, opts) do
    opts = Keyword.validate!(opts, sheet: nil, hidden: false)
    sheet = Keyword.fetch!(opts, :sheet)
    hidden = Keyword.fetch!(opts, :hidden)

    validate_sheet(sheet)
    validate_hidden(hidden)

    with {:ok, workbook} <- workbook(source) do
      sheet_names(workbook, sheet, hidden)
    end
  end

  @spec classify_sheets(Refract.source(), [Refract.Shape.t() | module()], keyword()) ::
          {:ok, [{String.t(), {:ok, Refract.Classify.Result.t()} | {:error, term()}}]}
          | {:error, term()}

  def classify_sheets(source, shapes, opts \\ []) do
    {sheet_opts, classify_opts} = Keyword.split(opts, [:sheet, :hidden])

    with {:ok, sheets} <- sheets(source, sheet_opts) do
      {:ok,
       Enum.map(sheets, &{&1, classify(source, shapes, Keyword.put(classify_opts, :sheet, &1))})}
    end
  end

  @spec encode(Enumerable.t(), [encode_opt()]) :: Enumerable.t()

  @impl Refract.Writer
  def encode(rows, opts) do
    opts = Keyword.validate!(opts, header: nil, sheet: "Sheet1")
    header = Keyword.fetch!(opts, :header)
    sheet = Keyword.fetch!(opts, :sheet)

    validate_sheet_name(sheet)

    worksheet = Exceed.Worksheet.new(sheet, nil, content(rows, header))

    "refract"
    |> Exceed.Workbook.new()
    |> Exceed.Workbook.add_worksheet(worksheet)
    |> Exceed.stream!()
  end

  defp content(rows, header) do
    rows
    |> Refract.Writer.cells(header)
    |> Stream.map(fn cells -> Enum.map(cells, &value/1) end)
    |> at_least_one_line()
  end

  defp at_least_one_line(lines) do
    Stream.transform(
      lines,
      fn -> :empty end,
      fn line, _state -> {[line], :written} end,
      &end_of_lines/1,
      fn _state -> :ok end
    )
  end

  defp end_of_lines(:empty), do: {[[]], :empty}
  defp end_of_lines(:written), do: {[], :written}

  defp value(%Time{} = time), do: Time.to_iso8601(time)
  defp value(value), do: value

  defp validate_sheet_name(sheet) when is_binary(sheet), do: :ok

  defp validate_sheet_name(sheet) do
    raise ArgumentError, "sheet must be a name, got: #{inspect(sheet)}"
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

  defp sheet_names(workbook, nil, hidden), do: {:ok, candidates(workbook, hidden)}

  defp sheet_names(workbook, sheet, hidden) do
    with {:ok, name} <- sheet_name(workbook, sheet, hidden), do: {:ok, [name]}
  end

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
