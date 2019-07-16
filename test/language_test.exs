defmodule LanguageTest do
  use ExUnit.Case

  import AutocheckLanguage
  alias AutocheckLanguage.Error

  @default_valid_env """
  @env "elixir",
    version: "1.7"
  """

  @default_valid_step """
  step "Test 1" do
    run "this should work"
  end
  """

  test "configuration with one top level statement" do
    assert {:ok, _} = parse(@default_valid_env)
  end

  test "configuration with multiple top level statements" do
    code =
      @default_valid_env <>
        @default_valid_step <>
        """
        step "Test 2" do
          run "something"
        end
        """

    assert {:ok, _} = parse(code)
  end

  test "configuration without unique step names" do
    code = @default_valid_env <> @default_valid_step <> @default_valid_step

    assert {:error, [%Error{description: description}]} = parse(code)
    assert String.contains?(description, "already been defined")
  end

  test "configuration with undefined env" do
    code = """
      @env "invalid"
    """

    assert {:error, [%Error{description: description}]} = parse(code)
    assert String.contains?(description, "environment is not defined")
  end

  test "configuration with empty step" do
    code = """
    @env "elixir",
      version: "1.7"

    step "empty" do
    end
    """

    assert {:ok, _} = parse(code)
  end

  test "configuration with empty required_files" do
    code = """
    @env "elixir",
      version: "1.7"

    @required_files

    step "random" do
      run "date"
    end
    """

    assert {:error, [%Error{description: description}]} = parse(code)
  end

  test "configuration with empty allowed_file_extensions" do
    code = """
    @env "elixir",
      version: "1.7"

    @allowed_file_extensions

    step "random" do
      run "date"
    end
    """

    assert {:error, [%Error{description: description}]} = parse(code)
  end

  test "configuration with grade" do
    code = fn grade ->
      """
      @env "elixir",
        version: "1.7"

      @grade #{grade}

      step "random" do
        run "date"
      end
      """
    end

    assert {:ok, _} = parse(code.("1"))
    assert {:ok, _} = parse(code.("1.0"))
    assert {:ok, _} = parse(code.("0.5"))
    assert {:ok, _} = parse(code.("0"))
    assert {:error, _} = parse(code.("a"))
    assert {:ok, _} = parse(code.("0x0"))
    assert {:error, _} = parse(code.("nil"))
    assert {:error, _} = parse(code.(":atom"))
    assert {:error, _} = parse(code.("2"))
    assert {:error, _} = parse(code.("-1"))
  end

  test "configuration with variables" do
    code = """
    g = 0.5
    i = "haskell"
    f = "Lab1.hs"

    @env "custom",
      image: i
    @grade g


    step "random" do
      run "cat %f"
    end
    """

    assert {:ok,
            %AutocheckLanguage{
              steps: steps,
              grade: grade,
              image: image
            }} = parse(code) |> IO.inspect()

    assert grade == 0.5
    assert image == "haskell"
    assert [%{commands: [["run", ["cat Lab1.hs"]]]}] = steps
  end
end
