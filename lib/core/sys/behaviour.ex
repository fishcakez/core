defmodule Core.Sys.Behaviour do
  @moduledoc """
  This module is a convenience module for adding the `Core.Sys` behaviour,
  automatically implementing the 4 optional callbacks and requring the
  `Core.Sys` module (for using the `Core.Sys.receive/4` macro).

  ## Examples

      defmodule PingPong do

          use Core.Behaviour
          use Core.Sys.Behaviour

          @spec ping(Core.t) :: :pong
          def ping(process), do: Core.call(process, __MODULE__, :ping, 5000)

          @spec count(Core.t) :: non_neg_integer
          def count(process), do: Core.call(process, __MODULE__, :count, 5000)

          @spec close(Core.t) :: :ok
          def close(process), do: Core.call(process, __MODULE__, :close, 5000)

          # die/1 will print alot of information because the exit reason is abnormal.
          @spec die(Core.t) :: :ok
          def die(process), do: Core.call(process, __MODULE__, :die, 5000)

          @spec start_link() :: { :ok, pid }
          def start_link() do
            Core.start_link(nil, __MODULE__, nil,
              [{ :debug, [{ :log, 10 }, { :stats, true }] }])
          end

          ## Core api

          def init(parent, debug, _args) do
            Core.init_ack()
            loop(0, parent, debug)
          end

          ## Core.Sys (minimal) api

          def system_continue(count, parent, debug), do: loop(count, parent, debug)

          def system_terminate(count, parent, debug, reason) do
            terminate(count, parent, debug, reason)
          end

          ## Internal

          defp loop(count, parent, debug) do
            Core.Sys.receive(__MODULE__, count, parent, debug) do
              { __MODULE__, from, :ping } ->
                # It is not required to record events using `Core.Debug.event/1` but is
                # a useful debug feature that is compiled to a no-op in production.
                debug = Core.Debug.event(debug, { :in, :ping, elem(from, 0) })
                Core.reply(from, :pong)
                debug = Core.Debug.event(debug, { :out, :pong, elem(from, 0) })
                count = count + 1
                debug = Core.Debug.event(debug, { :count, count })
                loop(count, parent, debug)
              { __MODULE__, from, :count } ->
                debug = Core.Debug.event(debug, { :in, :count, elem(from, 0) })
                Core.reply(from, count)
                debug = Core.Debug.event(debug, { :out, count, elem(from, 0) })
                loop(count, parent, debug)
              { __MODULE__, from, :close } ->
                debug = Core.Debug.event(debug, { :in, :close, elem(from, 0) })
                Core.reply(from, :ok)
                debug = Core.Debug.event(debug, { :out, :ok, elem(from, 0)  })
                terminate(count, parent, debug, :normal)
              { __MODULE__, from, :die } ->
                debug = Core.Debug.event(debug, { :in, :die, elem(from, 0) })
                Core.reply(from, :ok)
                debug = Core.Debug.event(debug, { :out, :ok, elem(from, 0)  })
                terminate(count, parent, debug, :die)
            end
          end

          defp terminate(count, parent, debug, reason) do
            event = { :EXIT, reason }
            debug = Core.Debug.event(debug, event)
            Core.stop(__MODULE__, count, parent, debug, reason, event)
          end

        end

  """
    defmacro __using__(_options) do
    quote location: :keep do

      @behaviour Core.Sys
      require Core.Sys

      @doc false
      def system_get_state(data), do: data

      def system_update_state(data, update) do
        data = update.(data)
        { data, data }
      end

      def system_get_data(data), do: data

      def system_change_data(data, _module, _vsn, _extra), do: data

      defoverridable [system_get_state: 1, system_update_state: 2,
        system_get_data: 1, system_change_data: 4]

    end
  end

end
