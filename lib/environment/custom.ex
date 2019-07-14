defmodule AutocheckLanguage.Environment.Custom do
  @behaviour AutocheckLanguage.Environment

  def image({:image, image}) do
    {:ok, image}
  end
end
