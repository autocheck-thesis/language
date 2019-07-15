defmodule AutocheckLanguage.Environment.Custom do
  use AutocheckLanguage.Environment

  def image({:image, image}) do
    {:ok, image}
  end
end
