defmodule AutocheckLanguage.Environment.Java do
  use AutocheckLanguage.Environment

  def image({:version, version}) when is_binary(version) or is_number(version) do
    {:ok, "openjdk:#{version}-slim"}
  end

  def image({:version, version}) do
    {:error, "unsupported image version: ", version}
  end
end
