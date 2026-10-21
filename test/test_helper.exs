exclude = if System.find_executable("soffice"), do: [], else: [:libreoffice]

ExUnit.start(exclude: exclude)
