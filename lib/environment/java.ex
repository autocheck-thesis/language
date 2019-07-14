defmodule AutocheckLanguage.Environment.Java do
  @behaviour AutocheckLanguage.Environment

  def image({:version, version}) when is_binary(version) or is_number(version) do
    {:ok, "openjdk:#{version}-slim"}
  end

  def image({:version, version}) do
    {:error, "unsupported image version: ", version}
  end

  def image({badarg, _}) do
    {:error, "incorrect parameter: ", badarg}
  end

  def image(_) do
    {:error, "syntax error", ""}
  end
end
