defmodule AutocheckLanguage.Environment do
  @callback image(any()) :: {:ok, String.t()}
end
