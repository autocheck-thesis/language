defmodule AutocheckLanguage do
  defmodule Error do
    defstruct [:line, :description, :token, description_suffix: ""]
  end

  defstruct image: nil,
            environment: nil,
            required_files: [],
            allowed_file_extensions: [],
            grade: nil,
            network_access: false,
            variables: %{},
            steps: [],
            errors: []

  # {name, arity}

  @built_in_functions [:run, :print]
  @built_in_functions_with_arity [
    {:run, 1},
    {:print, 1}
  ]

  @keywords [
    :@,
    :step
  ]

  @fields [
    :env,
    :required_files,
    :allowed_file_extensions,
    :grade,
    :network_access
  ]

  @environments %{
    "custom" => AutocheckLanguage.Environment.Custom,
    "elixir" => AutocheckLanguage.Environment.Elixir,
    "java" => AutocheckLanguage.Environment.Java
  }

  def parse_dsl_raw(dsl) do
    Code.string_to_quoted!(dsl)
  end

  def parse(configuration_code) do
    # Opts "existing_atoms_only" would make this function call safe, but also removes
    # the possiblity of descriptive error messages.
    case Code.string_to_quoted(configuration_code) do
      {:ok, quouted_form} ->
        case parse_top_level(quouted_form) do
          %AutocheckLanguage{errors: []} = state ->
            {:ok, state}

          %AutocheckLanguage{errors: errors} ->
            {:error, errors}
        end

      {:error, {line, {description_prefix, description_suffix}, token}} ->
        {:error,
         [
           %Error{
             line: line,
             description: description_prefix,
             token: token,
             description_suffix: description_suffix
           }
         ]}

      {:error, {line, description, token}} ->
        {:error, [%Error{line: line, description: description |> String.trim(), token: token}]}
    end
  end

  def parse!(configuration_code) do
    case parse(configuration_code) do
      {:ok, configuration} ->
        configuration

      {:error, errors} ->
        errors
        |> Enum.map(fn %Error{
                         line: line,
                         description: description,
                         token: token,
                         description_suffix: description_suffix
                       } ->
          "Line #{line}: #{description}#{token}. #{description_suffix}"
        end)
        |> Enum.join("\n")
        |> raise()
    end
  end

  # Multiple top level statements
  defp parse_top_level({:__block__, [], statements}), do: parse_top_level(statements)

  # One top level statement
  defp parse_top_level(statement) when not is_list(statement), do: parse_top_level([statement])

  defp parse_top_level(statements),
    do: Enum.reduce(statements, %AutocheckLanguage{}, &parse_statement(&1, &2))

  # Environment (env) field
  defp parse_statement(
         {:@, _meta, [{:env, [line: line], params}]},
         state
       ) do
    case params do
      [name, params] when is_list(params) ->
        parse_environment_field(name, params, line, state)

      [name] ->
        parse_environment_field(name, [], line, state)

      [] ->
        add_error(state, line, "missing environment name", "", "")

      _ ->
        add_error(state, line, "syntax error", "", "")
    end
  end

  # Required files field
  defp parse_statement(
         {:@, _meta, [{:required_files, [line: line], nil}]},
         state
       ),
       do: add_error(state, line, "list can not be empty: ", "required_files", "")

  defp parse_statement(
         {:@, _meta, [{:required_files, _meta2, file_names}]},
         state
       ),
       do: %{state | required_files: file_names}

  # Allowed file extensions field
  defp parse_statement(
         {:@, _meta, [{:allowed_file_extensions, [line: line], nil}]},
         state
       ),
       do: add_error(state, line, "list can not be empty: ", "allowed_file_extensions", "")

  defp parse_statement(
         {:@, _meta, [{:allowed_file_extensions, [line: line], allowed_file_extensions}]},
         state
       ) do
    case Enum.reject(allowed_file_extensions, fn ext ->
           is_binary(ext) and String.match?(ext, ~r/^(\.\w+)+$/)
         end) do
      [] ->
        %{state | allowed_file_extensions: allowed_file_extensions}

      badargs ->
        Enum.reduce(
          badargs,
          state,
          &add_error(
            &2,
            line,
            "Invalid file extension: ",
            map_keyword(&1),
            "A file extension must start with a dot and not contain any special characters."
          )
        )
    end
  end

  # Grade field
  defp parse_statement(
         {:@, meta, [{:grade, meta2, [{name, _meta2, _params}]}]},
         state
       ),
       do: parse_statement({:@, meta, [{:grade, meta2, [variable(state, name)]}]}, state)

  defp parse_statement(
         {:@, _meta, [{:grade, [line: line], [grade_percentage]}]},
         state
       )
       when (is_float(grade_percentage) or is_integer(grade_percentage)) and
              (grade_percentage < 0 or grade_percentage > 1),
       do: add_error(state, line, "grade must be a value between 0 and 1", "", "")

  defp parse_statement(
         {:@, _meta, [{:grade, _meta2, [grade_percentage]}]},
         state
       )
       when is_float(grade_percentage) or
              is_integer(grade_percentage),
       do: %{state | grade: grade_percentage}

  # Network access field
  defp parse_statement(
         {:@, meta, [{:network_access, meta2, [{name, _meta2, _params}]}]},
         state
       ),
       do: parse_statement({:@, meta, [{:network_access, meta2, [variable(state, name)]}]}, state)

  defp parse_statement(
         {:@, _meta, [{:network_access, [line: line], [boolean]}]},
         state
       )
       when not is_boolean(boolean),
       do: add_error(state, line, "network_access must be a boolean true or false", "", "")

  defp parse_statement(
         {:@, _meta, [{:network_access, _meta2, [boolean]}]},
         state
       ),
       do: %{state | network_access: boolean}

  # Unsupported field
  defp parse_statement({:@, _meta, [{field, [line: line], _params}]}, state)
       when field not in @fields do
    suggestion = suggest_similar_field(field)
    add_error(state, line, "incorrect field: ", field, suggestion)
  end

  # Invalid field syntax
  defp parse_statement({:@, _meta, [{_, [line: line], _params}]}, state),
    do: add_error(state, line, "syntax error", "", "")

  # Variable
  defp parse_statement({:=, _meta, [{name, _meta2, _params}, value]}, state),
    do: add_variable(state, name, value)

  # Empty step
  defp parse_statement({:step, _meta, [_step_name, [do: {:__block__, [], []}]]}, state),
    do: state

  # Step with multiple params
  defp parse_statement({:step, meta, [step_name, [do: {:__block__, [], step_params}]]}, state),
    do: parse_statement(step_name, meta, step_params, state)

  # Step with one param
  defp parse_statement({:step, meta, [step_name, [do: step_param]]}, state),
    do: parse_statement(step_name, meta, [step_param], state)

  defp parse_statement({keyword, [line: line], _params}, state) do
    suggestion = suggest_similar_keyword(keyword)
    add_error(state, line, "incorrect keyword: ", keyword, suggestion)
  end

  defp parse_statement(step_name, [line: line], step_params, state) do
    commands =
      Enum.map(step_params, fn x -> parse_step_command(x, state) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    if Enum.any?(state.steps, &(Map.fetch!(&1, :name) == step_name)) do
      add_error(state, line, "the step name has already been defined: ", step_name, "")
    else
      case commands do
        %{error: errors, ok: commands} ->
          %{
            state
            | steps: state.steps ++ [%{name: step_name, commands: commands}],
              errors: state.errors ++ errors
          }

        %{ok: commands} ->
          %{state | steps: state.steps ++ [%{name: step_name, commands: commands}]}

        %{error: errors} ->
          %{state | errors: state.errors ++ errors}
      end
    end
  end

  defp parse_environment_field(environment, environment_params, line, state) do
    environment_params =
      for param <- environment_params do
        case param do
          {key, {name, _meta, _params}} -> {key, variable(state, name)}
          param -> param
        end
      end

    case Map.get(@environments, variable(state, environment), :undefined) do
      :undefined ->
        suggestion = suggest_similar_environment(environment)
        add_error(state, line, "environment is not defined: ", environment, suggestion)

      environment_module ->
        image_param_counts =
          apply(environment_module, :__info__, [:functions])
          |> Keyword.get_values(:image)

        param_count = length(environment_params)

        if param_count in image_param_counts do
          case apply(environment_module, :image, environment_params) do
            {:ok, image} -> %{state | environment: environment_module, image: image}
            {:error, description, token} -> add_error(state, line, description, token, "")
          end
        else
          add_error(state, line, "incorrect number of parameters for env: ", environment, "")
        end
    end
  end

  defp parse_step_command({key, _meta, params}, state) when key in @built_in_functions,
    do: {:ok, [to_string(key), variable(state, params)]}

  defp parse_step_command({function, [line: line], _params}, %AutocheckLanguage{environment: nil}) do
    {:error, create_error(line, "undefined function: ", function, "")}
  end

  defp parse_step_command({function, [line: line], params}, state) do
    imported_functions = apply(state.environment, :__info__, [:functions])

    params = variable(state, params)

    cond do
      {function, length(params || [])} in imported_functions ->
        case apply(state.environment, function, params || []) do
          {:ok, _} = result -> result
          {:error, description, token} -> {:error, create_error(line, description, token, "")}
        end

      Keyword.has_key?(imported_functions, function) ->
        {:error,
         create_error(
           line,
           "incorrect amount of paramters for function: ",
           Atom.to_string(function) <> "/#{Keyword.fetch!(imported_functions, function)}",
           ""
         )}

      true ->
        suggestion = suggest_similar_function(function, imported_functions)

        {:error, create_error(line, "undefined function: ", function, suggestion)}
    end
  end

  defp suggest_similar_environment(environment) do
    Map.keys(@environments)
    |> find_suggestion(environment)
  end

  defp suggest_similar_keyword(keyword) do
    @keywords
    |> Enum.map(fn k -> to_string(k) end)
    |> find_suggestion(to_string(keyword))
  end

  defp suggest_similar_field(field) do
    @fields
    |> Enum.map(fn f -> to_string(f) end)
    |> find_suggestion(to_string(field))
  end

  defp suggest_similar_function(function, functions) do
    (@built_in_functions_with_arity ++ functions)
    |> Enum.map(fn {fun, _arity} -> to_string(fun) end)
    |> find_suggestion(to_string(function))
  end

  defp find_suggestion(strs, str) do
    strs
    |> Enum.map(fn s -> {s, String.jaro_distance(s, str)} end)
    |> Enum.filter(fn {_s, distance} -> distance > 0.8 end)
    |> Enum.max_by(fn {_s, distance} -> distance end, fn -> :no_similar end)
    |> case do
      :no_similar -> ""
      {s, _distance} -> "Did you mean #{s}?"
    end
  end

  defp add_variable(%{variables: variables} = state, name, value),
    do: %{state | variables: Map.put(variables, name, value)}

  defp variable(state, names) when is_list(names) do
    for name <- names, do: variable(state, name)
  end

  defp variable(%{variables: variables} = _state, name) when is_atom(name) do
    Map.get(variables, name)
  end

  defp variable(%{variables: variables} = _state, string) when is_binary(string) do
    Regex.replace(~r/%(\w+)/, string, fn _, name ->
      Map.get(variables, String.to_atom(name), "%" <> name)
    end)
  end

  defp variable(_state, name) do
    name
  end

  defp add_error(state, %Error{} = error), do: %{state | errors: state.errors ++ [error]}

  defp add_error(state, line, description, token, description_suffix)
       when is_list(token) or is_tuple(token),
       do:
         add_error(
           state,
           create_error(line, description, "[unsafe, can't render]", description_suffix)
         )

  defp add_error(state, line, description, token, description_suffix),
    do: add_error(state, create_error(line, description, token, description_suffix))

  defp create_error(line, description, token, description_suffix),
    do: %Error{
      line: line,
      description: description,
      token: token,
      description_suffix: description_suffix
    }

  defp map_keyword(keywords) when is_list(keywords),
    do: "[" <> (keywords |> Enum.map(&map_keyword(&1)) |> Enum.join(", ")) <> "]"

  defp map_keyword({keyword, _meta, _}), do: keyword
  defp map_keyword(other), do: inspect(other)
end
