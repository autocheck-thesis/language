defmodule AutocheckLanguage.Configuration do
  defstruct image: nil,
            required_files: [],
            allowed_file_extensions: [],
            grade: nil,
            steps: []
end
