defmodule Benchee.Formatters.Console do
  @moduledoc """
  Formatter to transform the statistics output into a structure suitable for
  output through `IO.write` on the console.
  """

  @behaviour Benchee.Formatter

  alias Benchee.{
    Statistics, Suite, Benchmark.Scenario, Configuration, Conversion
  }
  alias Benchee.Conversion.{Count, Duration, Unit, DeviationPercent}

  @type unit_per_statistic :: %{atom => Unit.t}

  @default_label_width 4 # Length of column header
  @ips_width 13
  @average_width 15
  @deviation_width 11
  @median_width 15
  @percentile_width 15
  @minimum_width 15
  @maximum_width 15
  @sample_size_width 15
  @mode_width 25
  @descriptor_label_width %{
    job_name: %{
      width: @default_label_width,
      label: "Name",
      format_str_pattern: "~*s"
    },
    ips: %{
      width: @ips_width,
      label: "ips",
      format_str_pattern: "~*s"
    },
    average: %{
      width: @average_width,
      label: "average",
      format_str_pattern: "~*ts"
    },
    deviation: %{
      width: @deviation_width,
      label: "deviation",
      format_str_pattern: "~*ts"
    },
    median: %{
      width: @median_width,
      label: "median",
      format_str_pattern: "~*ts"
    },
    percentile: %{
      width: @percentile_width,
      label: "99th %",
      format_str_pattern: "~*ts"
    },
    minimum: %{
      width: @minimum_width,
      label: "minimum",
      format_str_pattern: "~*ts"
    },
    maximum: %{
      width: @maximum_width,
      label: "maximum",
      format_str_pattern: "~*ts"
    },
    sample_size: %{
      width: @sample_size_width,
      label: "sample size",
      format_str_pattern: "~*ts"
    },
    mode: %{
      width: @mode_width,
      label: "mode",
      format_str_pattern: "~*ts"
    }
  }
  @default_options [:job_name, :ips, :average, :deviation, :median, :percentile]

  @doc """
  Formats the benchmark statistics using `Benchee.Formatters.Console.format/1`
  and then prints it out directly to the console using `IO.write/1`
  """
  @spec output(Suite.t) :: Suite.t
  def output(suite = %Suite{}) do
    :ok = suite
          |> format
          |> write

    suite
  end

  @doc """
  Formats the benchmark statistics to a report suitable for output on the CLI.

  Returns a list of lists, where each list element is a group belonging to one
  specific input. So if there only was one (or no) input given through `:inputs`
  then there's just one list inside.

  ## Examples

  ```
  iex> scenarios = [
  ...>   %Benchee.Benchmark.Scenario{
  ...>     job_name: "My Job", input_name: "My input", run_time_statistics: %Benchee.Statistics{
  ...>       average: 200.0,ips: 5000.0,std_dev_ratio: 0.1, median: 190.0, percentiles: %{99 => 300.1}
  ...>     }
  ...>   },
  ...>   %Benchee.Benchmark.Scenario{
  ...>     job_name: "Job 2", input_name: "My input", run_time_statistics: %Benchee.Statistics{
  ...>       average: 400.0, ips: 2500.0, std_dev_ratio: 0.2, median: 390.0, percentiles: %{99 => 500.1}
  ...>     }
  ...>   }
  ...> ]
  iex> suite = %Benchee.Suite{
  ...>   scenarios: scenarios,
  ...>   configuration: %Benchee.Configuration{
  ...>     formatter_options: %{
  ...>       console: %{comparison: false, extended_options: false}
  ...>     },
  ...>     unit_scaling: :best
  ...>   }
  ...> }
  iex> Benchee.Formatters.Console.format(suite)
  [["\n##### With input My input #####", "\nName             ips        average  deviation         median         99th %\n",
  "My Job           5 K         200 μs    ±10.00%         190 μs      300.10 μs\n",
  "Job 2         2.50 K         400 μs    ±20.00%         390 μs      500.10 μs\n"]]

  ```

  """
  @spec format(Suite.t) :: [any]
  def format(%Suite{scenarios: scenarios, configuration: config}) do
    config = console_configuration(config)
    scenarios
    |> Enum.group_by(fn(scenario) -> scenario.input_name end)
    |> Enum.map(fn({input, scenarios}) ->
        [input_header(input) | format_scenarios(scenarios, config)]
      end)
  end

  @doc """
  Takes the output of `format/1` and writes that to the console.
  """
  @spec write(any) :: :ok | {:error, String.t}
  def write(output) do
    IO.write(output)
  rescue
    _ -> {:error, "Unknown Error"}
  end

  defp console_configuration(%Configuration{
                               formatter_options: %{console: config},
                               unit_scaling: scaling_strategy}) do
    if Map.has_key?(config, :unit_scaling), do: warn_unit_scaling()
    Map.put config, :unit_scaling, scaling_strategy
  end

  defp warn_unit_scaling do
    IO.puts "unit_scaling is now a top level configuration option, avoid passing it as a formatter option."
  end

  @no_input_marker Benchee.Benchmark.no_input()
  defp input_header(input) do
    case input do
      @no_input_marker -> ""
      _                -> "\n##### With input #{input} #####"
    end
  end

  @doc """
  Formats the job statistics to a report suitable for output on the CLI.

  ## Examples

  ```
  iex> scenarios = [
  ...>   %Benchee.Benchmark.Scenario{
  ...>     job_name: "My Job", run_time_statistics: %Benchee.Statistics{
  ...>       average: 200.0, ips: 5000.0,std_dev_ratio: 0.1, median: 190.0, percentiles: %{99 => 300.1},
  ...>       minimum: 100.1, maximum: 200.2, sample_size: 10_101, mode: 333.2
  ...>     }
  ...>   },
  ...>   %Benchee.Benchmark.Scenario{
  ...>     job_name: "Job 2", run_time_statistics: %Benchee.Statistics{
  ...>       average: 400.0, ips: 2500.0, std_dev_ratio: 0.2, median: 390.0, percentiles: %{99 => 500.1},
  ...>       minimum: 200.2, maximum: 400.4, sample_size: 20_202, mode: [612.3, 554.1]
  ...>     }
  ...>   }
  ...> ]
  iex> configuration = %{comparison: false, unit_scaling: :best, extended_options: true}
  iex> Benchee.Formatters.Console.format_scenarios(scenarios, configuration)
  ["\nName             ips        average  deviation         median         99th %\n",
  "My Job           5 K         200 μs    ±10.00%         190 μs      300.10 μs\n",
  "Job 2         2.50 K         400 μs    ±20.00%         390 μs      500.10 μs\n",
  "\nExtended options: \n",
  "\nName           minimum        maximum    sample size                     mode\n",
  "My Job       100.10 μs      200.20 μs          10101                333.20 μs\n",
  "Job 2        200.20 μs      400.40 μs          20202     612.30 μs, 554.10 μs\n"]

  ```

  """
  @spec format_scenarios([Scenario.t], map) :: [any, ...]
  def format_scenarios(scenarios, config) do
    sorted_scenarios = Statistics.sort(scenarios)
    %{unit_scaling: scaling_strategy} = config
    units = Conversion.units(sorted_scenarios, scaling_strategy)
    label_width = label_width(sorted_scenarios)

    label_width_overrides = %{job_name: -label_width}
    output = [column_descriptors(@default_options, label_width_overrides) |
      generic_scenario_reports(sorted_scenarios,
        @default_options, units, label_width_overrides)
      ++ comparison_report(sorted_scenarios, units, label_width, config)]

    extended_options = [:job_name | config.extended_options]
    if Enum.count(config.extended_options) > 0 do
      output ++ [descriptor("Extended options") |
        [extended_column_descriptors(extended_options, label_width_overrides)]
          ++ generic_scenario_reports(sorted_scenarios,
                extended_options, units, label_width_overrides)]
    else
      output
    end
  end

  @spec generic_scenario_reports([Scenario.t], [atom], map, map) :: [any, ...]
  defp generic_scenario_reports(scenarios, options, units, label_width_overrides) do
    Enum.map(scenarios, fn(scenario) ->
      generic_scenario_format(scenario, options, units, label_width_overrides) <> "\n"
    end)
  end

  @spec generic_scenario_format(Scenario.t, map, [atom], map) :: String.t
  defp generic_scenario_format(scenario = %Scenario{
                                  job_name: _name,
                                  run_time_statistics: %Statistics{
                                    minimum:     _minimum,
                                    maximum:     _maximum,
                                    sample_size: _sample_size,
                                    mode:        _mode
                                  },
                                },
                                options,
                                %{run_time: run_time_unit},
                                label_width_overrides) do
    template = Enum.map_join(options, fn(option) ->
      if !Map.has_key?(@descriptor_label_width, option) do
        raise "Unsupported console option: #{option}"
      end

      @descriptor_label_width[option].format_str_pattern
    end)

    format_array_list = Enum.map(options, fn(option) ->
      if !Map.has_key?(@descriptor_label_width, option) do
        raise "Unsupported console option: #{option}"
      end

      option_label_width = @descriptor_label_width[option]

      option_value = Map.get(scenario, option)
      value = if option_value == nil do
        run_time_stats = Map.get(scenario, :run_time_statistics)
        Map.get(run_time_stats, option)
      else
        option_value
      end

      if Map.has_key?(label_width_overrides, option) do
        [label_width_overrides[option], to_string(value)]
      else
        # TODO(lnw) This is where it gets a little weird...
        # we need to be able to call the correct formatting method with the 
        ## correct set of arguments - not sure how to accomplish this
        [option_label_width.width, to_string(value)]
      end
    end)

    format_array = Enum.concat(format_array_list)

    template
    |> :io_lib.format(format_array)
    |> to_string
    # "~*s~*ts~*ts~*ts~*ts\n"
    # |> :io_lib.format([
    #   -label_width, name,
    #   @minimum_width, run_time_out(minimum, run_time_unit),
    #   @maximum_width, run_time_out(maximum, run_time_unit),
    #   @sample_size_width, to_string(sample_size),
    #   @mode_width, mode_out(mode, run_time_unit)])
    # |> to_string
  end

  @spec mode_out([number], Benchee.Conversion.Unit.t) :: String.t
  defp mode_out(modes, run_time_unit) when is_list(modes) do
    Enum.map_join(modes, ", ", fn(mode) -> run_time_out(mode, run_time_unit) end)
  end
  defp mode_out(mode, run_time_unit) when is_number(mode) do
    run_time_out(mode, run_time_unit)
  end

  @spec extended_column_descriptors([atom], map) :: String.t
  defp extended_column_descriptors(options, label_width_overrides) do
    build_column_descriptors(options, "~*s", label_width_overrides)

    # "\n~*s~*s~*s~*s~*s\n"
    # |> :io_lib.format([-label_width, "Name", @minimum_width, "minimum",
    #                    @maximum_width, "maximum", @sample_size_width, "sample size",
    #                    @mode_width, "mode"])
    # |> to_string
  end

  @spec build_column_descriptors([atom], String.t, map) :: String.t
  defp build_column_descriptors(options, pattern, label_width_overrides) do
    template = "\n" <> Enum.map_join(options, fn(option) -> pattern end) <> "\n"

    format_array_list = Enum.map(options, fn(option) ->
      if !Map.has_key?(@descriptor_label_width, option) do
        raise "Unsupported console option: #{option}"
      end

      option_label_width = @descriptor_label_width[option]

      if Map.has_key?(label_width_overrides, option) do
        [label_width_overrides[option], option_label_width.label]
      else
        [option_label_width.width, option_label_width.label]
      end
    end)

    format_array = Enum.concat(format_array_list)

    template
    |> :io_lib.format(format_array)
    |> to_string
  end

  @spec column_descriptors([atom], map) :: String.t
  defp column_descriptors(options, label_width_overrides) do
    build_column_descriptors(options, "~*s", label_width_overrides)

    # "\n~*s~*s~*s~*s~*s~*s\n"
    # |> :io_lib.format([-label_width, "Name", @ips_width, "ips",
    #                    @average_width, "average",
    #                    @deviation_width, "deviation", @median_width, "median",
    #                    @percentile_width, "99th %"])
    # |> to_string
  end

  defp label_width(scenarios) do
    max_label_width =
      scenarios
      |> Enum.map(fn(scenario) -> String.length(scenario.job_name) end)
      |> Stream.concat([@default_label_width])
      |> Enum.max
    max_label_width + 1
  end

  # defp scenario_reports(scenarios, units, label_width) do
  #   Enum.map(scenarios,
  #            fn(scenario) -> format_scenario(scenario, units, label_width) end)
  # end

  # @spec format_scenario(Scenario.t, unit_per_statistic, integer) :: String.t
  # defp format_scenario(%Scenario{
  #                        job_name: name,
  #                        run_time_statistics: %Statistics{
  #                          average:       average,
  #                          ips:           ips,
  #                          std_dev_ratio: std_dev_ratio,
  #                          median:        median,
  #                          percentiles:   %{99 => percentile_99}
  #                        }
  #                      },
  #                      %{run_time: run_time_unit,
  #                        ips:      ips_unit,
  #                      }, label_width) do
  #   "~*s~*ts~*ts~*ts~*ts~*ts\n"
  #   |> :io_lib.format([
  #     -label_width, name,
  #     @ips_width, ips_out(ips, ips_unit),
  #     @average_width, run_time_out(average, run_time_unit),
  #     @deviation_width, deviation_out(std_dev_ratio),
  #     @median_width, run_time_out(median, run_time_unit),
  #     @percentile_width, run_time_out(percentile_99, run_time_unit)])
  #   |> to_string
  # end

  defp ips_out(ips, unit) do
    Count.format({Count.scale(ips, unit), unit})
  end

  defp run_time_out(run_time, unit) do
    Duration.format({Duration.scale(run_time, unit), unit})
  end

  defp deviation_out(std_dev_ratio) do
    DeviationPercent.format(std_dev_ratio)
  end

  @spec comparison_report([Scenario.t], unit_per_statistic, integer, map)
    :: [String.t]
  defp comparison_report(scenarios, units, label_width, config)
  defp comparison_report([_scenario], _, _, _) do
    [] # No need for a comparison when only one benchmark was run
  end
  defp comparison_report(_, _, _, %{comparison: false}) do
    []
  end
  defp comparison_report([scenario | other_scenarios], units, label_width, _) do
    [
      descriptor("Comparison"),
      reference_report(scenario, units, label_width) |
      comparisons(scenario, units, label_width, other_scenarios)
    ]
  end

  defp reference_report(%Scenario{job_name: name,
                                  run_time_statistics: %Statistics{ips: ips}},
                        %{ips: ips_unit}, label_width) do
    "~*s~*s\n"
    |> :io_lib.format([-label_width, name, @ips_width, ips_out(ips, ips_unit)])
    |> to_string
  end

  @spec comparisons(Scenario.t, unit_per_statistic, integer, [Scenario.t])
    :: [String.t]
  defp comparisons(%Scenario{run_time_statistics: reference_stats},
                   units, label_width, scenarios_to_compare) do
    Enum.map(scenarios_to_compare,
      fn(scenario = %Scenario{run_time_statistics: job_stats}) ->
        slower = (reference_stats.ips / job_stats.ips)
        format_comparison(scenario, units, label_width, slower)
      end
    )
  end

  defp format_comparison(%Scenario{job_name: name,
                                   run_time_statistics: %Statistics{ips: ips}},
                         %{ips: ips_unit}, label_width, slower) do
    ips_format = ips_out(ips, ips_unit)
    "~*s~*s - ~.2fx slower\n"
    |> :io_lib.format([-label_width, name, @ips_width, ips_format, slower])
    |> to_string
  end

  @spec descriptor(String.t) :: String.t
  defp descriptor(header_str) do
    "\n#{header_str}: \n"
  end
end
