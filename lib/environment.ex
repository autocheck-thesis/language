defmodule AutocheckLanguage.Environment do
  defmacro __using__(_) do
    quote do
      @behaviour AutocheckLanguage.Environment

      @before_compile AutocheckLanguage.Environment
    end
  end

  @callback image(any()) :: {:ok, String.t()}

  defmacro __before_compile__(_env) do
    quote do
      def image({badarg, _}) do
        {:error, "incorrect parameter: ", badarg}
      end

      def image(_) do
        {:error, "syntax error", ""}
      end
    end
  end
end
