defmodule Core.Sys do

  use Behaviour

  @doc """
  Returns the state of the process.
  """
  defcallback system_get_state(data) :: state

  @doc """
  Updates the state of the process.
  """
  defcallback system_update_state(data, update) :: { state, data }

  @doc """
  Returns all data about the process.
  """
  defcallback system_get_data(data) :: data

  @doc """
  Changes the data for use with a different version of a module.
  """
  defcallback system_change_data(data, module, vsn, extra) :: data

  @doc """
  Called when the process should re-enter it's loop after handling
  system messages.
  """
  defcallback system_continue(data, Core.parent) :: no_return

  @doc """
  Called when the process should terminate after handling system
  messages, i.e. an exit signal was received from the parent process
  when the current process is trapping exits.
  """
  defcallback system_terminate(data, Core.parent, any) ::
    no_return

  ## types

  @typep data :: any
  @typep state :: any
  @typep update :: ((data) -> { state, data })
  @typep vsn :: any
  @typep extra :: any
  @type status :: map

  ## exceptions

  defexception CallbackError, [action: nil, reason: nil] do
    def message(exception) do
      case normalize(exception.reason) do
        exception2 when is_exception(exception2) ->
          "#{format_action(exception.action)} raised an exception\n" <>
          "   (#{inspect(elem(exception2, 0))}) #{exception2.message}"
        { :EXIT, reason } ->
          "#{format_action(exception.action)} exited with reason: " <>
          "#{inspect(reason)}"
      end
    end

    defp format_action(nil), do: "unknown function"
    defp format_action(fun), do: inspect(fun)

    defp normalize(exception) when is_exception(exception), do: exception
    # Exception.format_stacktrace() will return a new stacktrace when
    # stack is nil
    defp normalize({ :EXIT, { _error, nil } } = reason), do: reason

    defp normalize({ :EXIT, { error, stack } = reason }) do
      try do
        Exception.format_stacktrace(stack)
      else
        # assume is stacktrace
        _formatted_stack ->
          Exception.normalize(error)
      rescue
        # definitely not a stacktrace
        _exception ->
          { :EXIT, reason }
      end
    end

    defp normalize({ :EXIT, _reason } = reason), do: reason

  end

  defexception CatchLevelError, [level: nil] do
    def message(exception) do
      case exception.level do
        0 ->
          "process was not started by Core or did not use Core to hibernate"
        # level is 3 or more
        level ->
          "Core.Sys loop was not entered by a tail call, #{level-2} catch(es)"
      end
    end
  end

  ## macros

  @doc """
  Macro to handle system messages but not receive any other messages.

  `mod.system_continue/2` or `mod.system_terminate/3` will return
  control of the process to `mod` after handling system messages.

  Should only be used as a tail call as it has no local return.
  """
  defmacro receive(mod, data, parent) do
    parent_quote = quote do: parent_var
    extra = transform_receive(mod, data, parent_quote)
    quote do
      parent_var = unquote(parent)
      receive do: unquote(extra)
    end
  end

  @doc """
  Macro to handle system messages and receive messages.

  `mod.system_continue/2` or `mod.system_terminate/3` will return
  control of the process to `mod` after handling system messages.

  Should only be used as a tail call as it has no local return.

  ## Examples

      use Core.Sys.Behaviour

      defp loop(data, parent) do
        Core.Sys.receive(__MODULE__, data, parent) do
          msg ->
            IO.puts(:stdio, inspect(msg))
            loop(data, parent)
        after
          1000 ->
            terminate(data, parent, timeout)
        end
      end

      def system_continue(data, parent) do
        loop(data, parent)
      end

      def system_terminate(data, parent,, reason) do
        terminate(data, parent, reason)
      end

      defp terminate(data, parent, reason) do
        exit(reason)
      end

  """
  defmacro receive(mod, data, parent, do: do_clauses) do
    parent_quote = quote do: parent_var
    extra = transform_receive(mod, data, parent_quote)
    quote do
      parent_var = unquote(parent)
      receive do: unquote(extra ++ do_clauses)
    end
  end

  defmacro receive(mod, data, parent, do: do_clauses, after: after_clause) do
    parent_quote = quote do: parent_var
    extra = transform_receive(mod, data, parent_quote)
    quote do
      parent_var = unquote(parent)
      receive do: unquote(extra ++ do_clauses), after: unquote(after_clause)
    end
  end

  defmacrop default_timeout(), do: 5000

  ## system api

  @doc """
  Pings an OTP process to see if it is responsive to system messages.
  Returns `:pong` on success.
  """
  @spec ping(Core.t, timeout) :: :pong
  def ping(process, timeout \\ default_timeout()) do
    { :error, { :unknown_system_msg, :ping } } = call(process, :ping, timeout)
    :pong
  end

  @doc """
  Suspends an OTP process so that it can only handle system messages.
  """
  @spec suspend(Core.t, timeout) :: :ok
  def suspend(process, timeout \\ default_timeout()) do
    call(process, :suspend, timeout)
  end

  @doc """
  Resumes an OTP process that has been system suspended.
  """
  @spec resume(Core.t, timeout) :: :ok
  def resume(process, timeout \\ default_timeout()) do
    call(process, :resume, timeout)
  end

  @doc """
  Returns the state of an OTP process.
  """
  @spec get_state(Core.t, timeout) :: state
  def get_state(process, timeout \\ default_timeout()) do
    state_call(process, :get_state, timeout)
  end

  @doc """
  Sets the state of an OTP process.
  """
  @spec set_state(Core.t, state, timeout) :: :ok
  def set_state(process, state, timeout \\ default_timeout()) do
    update = fn(_old_state) -> state end
    ^state = state_call(process, { :replace_state, update }, timeout)
    :ok
  end

  @doc """
  Updates the state of an OTP process.
  Returns the updated state.
  """
  @spec update_state(Core.t, update, timeout) :: state
  def update_state(process, update, timeout \\ default_timeout()) do
    state_call(process, { :replace_state, update }, timeout)
  end

  @doc """
  Returns status information about an OTP process.

  This function will return alot of information, including the process
  dictionary of the target process.
  """
  @spec get_status(Core.t, timeout) :: status
  def get_status(process, timeout \\ default_timeout()) do
    call(process, :get_status, timeout)
      |> parse_status()
  end

  @doc """
  Returns the data held about an OTP process.

  This function will return any data held about a process. In many cases
  this will return the same as `get_state/2`.
  """
  @spec get_data(Core.t, timeout) :: data | nil
  def get_data(process, timeout \\ default_timeout()) do
    get_status(process, timeout)
      |> Dict.get(:data)
  end

  @doc """
  Change the data of an OTP process due to a module version change.

  Can only be used on system suspended processes.
  """
  @spec change_data(Core.t, module, vsn, extra, timeout) :: :ok
  def change_data(process, mod, oldvsn, extra, timeout \\ default_timeout()) do
    case state_call(process, { :change_code, mod, oldvsn, extra }, timeout) do
      :ok ->
        :ok
      # direct :sys module raised an error/exited
      { :error, { :EXIT, _ } = reason } ->
        raise Core.Sys.CallbackError[reason: reason]
      # direct :sys module did not return { :ok, data }
      { :error, other } ->
        raise Core.Sys.CallbackError[reason: MatchError[term: other]]
    end
  end

  ## receive macro api

  @doc false
  @spec message(__MODULE__, data, Core.parent, any, Core.from) ::
    no_return
  def message(mod, data, parent, :get_state, from) do
    handle_get_state([mod | data], parent, from)
  end

  def message(mod, data, parent, { :replace_state, replace}, from) do
    handle_replace_state([mod | data], parent, replace, from)
  end

  def message(mod, data, parent, msg, from) do
    :sys.handle_system_msg(msg, from, parent, __MODULE__, [], [mod | data])
  end

  ## :sys api

  @doc false
  def system_continue(parent, [], [mod | data]) do
    continue(mod, :system_continue, data, parent)
  end

  def system_continue(parent, _debug, [mod | data]) do
    # debug is not supported and debug options have been added. Exit as
    # will forget these options. Generate suitable exception/stacktrace.
    try do
      exception = FunctionClauseError[module: __MODULE__,
        function: :sytem_continue, arity: 3]
      raise Core.Sys.CallbackError,
        [action: &__MODULE__.system_continue/3, reason: exception]
    rescue
      exception ->
        reason = { exception, System.stacktrace() }
        system_terminate(parent, [], [mod | data], reason)
    end
  end

  @doc false
  def system_terminate(parent, _debug, [mod | data], reason) do
    continue(mod, :system_terminate, data, parent, [reason])
  end

  @doc false
  def system_get_state([mod | data]) do
    try do
      mod.system_get_state(data)
    else
      state ->
        { :ok, state }
    rescue
      # Callback failed in a callback of mod
      exception in [Core.Sys.CallbackError] ->
        raise exception, []
      exception ->
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_get_state, 1), reason: exception
    catch
      :throw, value ->
        exception = Core.UncaughtThrowError[actual: value]
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_get_state, 1), reason: exception
      :exit, reason ->
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_get_state, 1),
          reason: { :EXIT, reason }
    end
  end

  @doc false
  def system_replace_state(replace, [mod | data]) do
    try do
      { _state, _data} = mod.system_update_state(data, replace)
    else
      { state, data } ->
        { :ok, state, [mod | data] }
    rescue
      # Callback failed in a callback of mod
      exception in [Core.Sys.CallbackError] ->
        raise exception, []
      exception ->
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_update_state, 2),
          reason: exception
    catch
      :throw, value ->
        exception = Core.UncaughtThrowError[actual: value]
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_update_state, 2),
          reason: exception
      :exit, reason ->
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_update_state, 2),
          reason: { :EXIT, reason }
    end
  end

  @doc false
  def format_status(_type,
      [_pdict, sys_status, parent, _debug, [mod | data]]) do
    base_status = format_base_status(sys_status, parent, mod)
    try do
      mod.system_get_data(data)
    else
      mod_data ->
        base_status ++ [{ :data, [{ 'Module data', mod_data }] }]
    rescue
      exception ->
        exception2 = Core.Sys.CallbackError[
          action: :erlang.make_fun(mod, :system_get_data, 1),
          reason: exception]
        format_status_error(base_status, data, exception2)
    catch
      :throw, value ->
        exception = Core.UncaughtThrowError[actual: value]
        exception2 = Core.Sys.CallbackError[
          action: :erlang.make_fun(mod, :system_get_data, 1),
          reason: exception]
        format_status_error(base_status, data, exception2)
      :exit, reason ->
        exception = Core.Sys.CallbackError[
          action: :erlang.make_fun(mod, :system_get_data, 1),
          reason: { :EXIT, reason }]
        format_status_error(base_status, data, exception)
    end
  end

  @doc false
  def system_code_change([mod | data], change_mod, oldvsn, extra) do
    try do
      mod.system_change_data(data, change_mod, oldvsn, extra)
    else
      data ->
        { :ok, [mod | data] }
    rescue
      # Callback failed in a callback of mod.
      exception in [Core.Sys.CallbackError] ->
        code_change_error(exception)
      exception ->
        exception2 = Core.Sys.CallbackError[
          action: :erlang.make_fun(mod, :system_change_data, 4),
          reason: exception]
        code_change_error(exception2)
    catch
      :throw, value ->
        exception = Core.UncaughtThrowError[actual: value]
        exception2 = Core.Sys.CallbackError[
          action: :erlang.make_fun(mod, :system_change_data, 4),
          reason: exception]
        code_change_error(exception2)
      :exit, reason ->
        exception = Core.Sys.CallbackError[
          action: :erlang.make_fun(mod, :system_change_data, 4),
          reason: { :EXIT, reason }]
        code_change_error(exception)
    end
  end

  ## internal

  ## receive

  defp transform_receive(mod, data, parent) do
    quote do
      { :EXIT, ^unquote(parent), reason } ->
        unquote(mod).system_terminate(unquote(data), unquote(parent), reason)
      { :system, from, msg } ->
        Core.Sys.message(unquote(mod), unquote(data), unquote(parent), msg,
          from)
    end
  end

  ## calls

  defp call(process, request, timeout) do
    Core.call(process, :system, request, timeout)
  end

  defp state_call(process, request, timeout) do
    case call(process, request, timeout) do
      { :ok, result } ->
        result
      { :error, { :unknown_system_msg, { :change_code, _, _, _ } } } ->
        raise ArgumentError, message: "#{Core.format(process)} is running"
      { :error, { :unknown_system_msg, _request } } ->
        raise ArgumentError, message: "#{Core.format(process)} is suspended"
      :ok ->
        :ok
      # exception raised by this module, raise it.
      { :error, { :callback_failed, { __MODULE__, _ }, { :error, exception } } }
          when is_exception(exception) ->
        raise exception, []
      # raised in a direct :sys module, normalize and raise.
      { :error, { :callback_failed, action, { :error, error } } } ->
        exception = Exception.normalize(error)
        raise Core.Sys.CallbackError, action: action, reason: exception
      # raised in a direct :sys  module, make exception and raise.
      { :error, { :callback_failed, action, { :throw, value } } } ->
        exception = Core.UncaughtThrowError[actual: value]
        raise Core.Sys.CallbackError, action: action, reason: exception
      # raised in a direct :sys module, raise with { :EXIT, reason }
      { :error, { :calback_failed, action, { :exit, reason } } } ->
        raise Core.Sys.CallbackError, action: action, reason: { :EXIT, reason }
      state ->
        state
    end
  end

  ## :sys api

  defp parse_status({ :status, pid, { :module, __MODULE__ },
        [pdict, sys_status, parent, _debug, status]}) do
    status_data = get_status_data(status)
    case get(status_data, 'Module error') do
      nil ->
        parse_status_data(pid, __MODULE__, pdict, sys_status, parent,
          status_data)
      { :callback_failed, { __MODULE__, _ }, { :error, exception } } ->
        raise exception, []
    end
  end

  defp parse_status({ :status, pid, { :module, mod },
        [pdict, sys_status, parent, _debug, status]}) do
    status_data = get_status_data(status)
    parse_status_data(pid, mod, pdict, sys_status, parent, status_data)
  end

  defp get_status_data(status) do
    try do
      data = Keyword.get_values(status, :data)
      # special case for :gen_event (or similar direct :sys)
      items = Keyword.get_values(status, :items)
      List.flatten([items, data])
    rescue
      # not formed as expected, pass whole status as state. Will be used
    # as data term later.
      exception ->
        IO.puts(:user, inspect(exception))
        [{ 'State', status }]
    end
  end

  defp parse_status_data(pid, mod, pdict, sys_status, parent, status_data) do
    name = get(status_data, 'Name', pid)
    mod2 = get(status_data, 'Module', mod)
    mod_data = get_mod_data(mod, status_data)
    %{ name: name, module: mod2, data: mod_data, pid: pid, dictionary: pdict,
      sys_status: sys_status, parent: parent }
  end

  defp get_mod_data(__MODULE__, status_data) do
    get(status_data, 'Module data')
  end

  defp get_mod_data(:gen_fsm, status_data) do
    state_name = get(status_data, 'StateName')
    state_data = get(status_data, 'StateData')
    { state_name, state_data }
  end

  defp get_mod_data(:gen_event, status_data) do
    to_data = fn({ :handler, mod, id, state, _sup }) -> { mod, id, state} end
    get(status_data, 'Installed handlers')
      |> Enum.map(to_data)
  end

  defp get_mod_data(_mod, status_data) do
    get(status_data, 'State', status_data)
  end

  # Mimic handling of 17.0. Once 17.0 is out this function will disappear.
  defp handle_get_state([mod | data], parent, from) do
    try do
      system_get_state([mod | data])
    else
      { :ok, _state } = response ->
        Core.reply(from, response)
        system_continue(parent, [], [mod | data])
    catch
      class, reason ->
        action = { __MODULE__, :get_state }
        reason2 = { :callback_failed, action, { class, reason } }
        Core.reply(from, { :error, reason2 })
        system_continue(parent, [], [mod | data])
    end
  end

  # Mimic handling of 17.0. Once 17.0 is out this function will disappear.
  defp handle_replace_state([mod | data], parent, replace, from) do
    try do
      { :ok, _state, _mod_data } = system_replace_state(replace, [mod | data])
    else
      { :ok, state, [mod | data] } ->
        Core.reply(from, { :ok, state })
        system_continue(parent, [], [mod | data])
    catch
      class, reason ->
        action = { __MODULE__, :replace_state }
        reason2 = { :callback_failed, action, { class, reason } }
        Core.reply(from, { :error, reason2 })
        system_continue(parent, [], [mod | data])
    end
  end

  defp format_base_status(sys_status, parent, mod) do
    header = String.to_char_list!("Status for #{inspect(mod)} #{Core.format()}")
    data = [{ 'Status', sys_status }, { 'Parent', parent },
      { 'Name', Core.get_name() }, { 'Module', mod }]
    [{ :header, header }, { :data, data }]
  end

  defp format_status_error(base_status, mod_data, exception) do
    reason = { :callback_failed, { __MODULE__, :format_status },
      { :error, exception } }
    mod_status = [{ :data,
        [{ 'Module data', mod_data }, { 'Module error', reason }] }]
    base_status ++ mod_status
  end

  defp code_change_error(exception) do
    # Does not match { :ok, data } causing { :error, { :callback_failed, ..}} to
    # be returned by :sys. This is the same form as the replace/get_state error
    # message returned in 17.0 final. Therefore even though it is handled
    # differently in :sys, to Core.Sys modules it will appear to be handled the
    # same as replace/get_state.
    { :callback_failed, { __MODULE__, :system_code_change },
      { :error, exception } }
  end

  defp continue(mod, fun, data, parent, args \\ []) do
    case Process.info(self(), :catchlevel) do
      # Assume :proc_lib catch but no Core catch due to hibernation.
      { :catchlevel, 1 } ->
        # Use Core to re-add Core catch for logging exceptions.
        Core.continue(mod, fun, data, parent, args)
      # Assume :proc_lib catch and Core catch, i.e. no hibernation.
      { :catchlevel, 2 } ->
        apply(mod, fun, [data, parent] ++ args)
      # Either not a Core/:proc_lib process OR
      # Core.Sys.receive/4 macro was used inside a catch.
      { :catchlevel, level } ->
        try do
          raise Core.Sys.CatchLevelError, level: level
        rescue
          exception ->
            # Hibernation didn't occur (level would be 1) so generate a
            # stacktrace (and exception), which hopefully will be logged by mod.
            reason = { exception, System.stacktrace()}
            # Use Core to add Core catch which may log an exception if one is
            # raised. If we have two levels (or more!) of the Core catch an
            # exception will only be logged once.
            Core.continue(mod, :system_terminate, data, parent, [reason])
        end
    end
  end

  ## util

  defp get(list, key, default \\ nil) do
    case List.keyfind(list, key, 0, nil) do
      nil ->
        default
      { _key, value } ->
        value
    end
  end

end
