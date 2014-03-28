defmodule Base.Sys.Behaviour do
  @moduledoc """
  This module is a convenience module for adding the `Base.Sys` behaviour,
  automatically implementing the 4 optional callbacks and requring the
  `Base.Sys` module (for using the `Base.Sys.receive/4` macro).

  ## Examples

      defmodule PingPong do

          use Base.Behaviour
          use Base.Sys.Behaviour

          @spec ping(Base.t) :: :pong
          def ping(process), do: Base.call(process, __MODULE__, :ping, 5000)

          @spec count(Base.t) :: non_neg_integer
          def count(process), do: Base.call(process, __MODULE__, :count, 5000)

          @spec close(Base.t) :: :ok
          def close(process), do: Base.call(process, __MODULE__, :close, 5000)

          # die/1 will print alot of information because the exit reason is abnormal.
          @spec die(Base.t) :: :ok
          def die(process), do: Base.call(process, __MODULE__, :die, 5000)

          @spec start_link() :: { :ok, pid }
          def start_link() do
            Base.start_link(nil, __MODULE__, nil,
              [{ :debug, [{ :log, 10 }, { :stats, true }] }])
          end

          ## Base api

          def init(parent, debug, _args) do
            Base.init_ack()
            loop(0, parent, debug)
          end

          ## Base.Sys (minimal) api

          def system_continue(count, parent, debug), do: loop(count, parent, debug)

          def system_terminate(count, parent, debug, reason) do
            terminate(count, parent, debug, reason)
          end

          ## Internal

          defp loop(count, parent, debug) do
            Base.Sys.receive(__MODULE__, count, parent, debug) do
              { __MODULE__, from, :ping } ->
                # It is not required to record events using `Base.Debug.event/1` but is
                # a useful debug feature that is compiled to a no-op in production.
                debug = Base.Debug.event(debug, { :in, :ping, elem(from, 0) })
                Base.reply(from, :pong)
                debug = Base.Debug.event(debug, { :out, :pong, elem(from, 0) })
                count = count + 1
                debug = Base.Debug.event(debug, { :count, count })
                loop(count, parent, debug)
              { __MODULE__, from, :count } ->
                debug = Base.Debug.event(debug, { :in, :count, elem(from, 0) })
                Base.reply(from, count)
                debug = Base.Debug.event(debug, { :out, count, elem(from, 0) })
                loop(count, parent, debug)
              { __MODULE__, from, :close } ->
                debug = Base.Debug.event(debug, { :in, :close, elem(from, 0) })
                Base.reply(from, :ok)
                debug = Base.Debug.event(debug, { :out, :ok, elem(from, 0)  })
                terminate(count, parent, debug, :normal)
              { __MODULE__, from, :die } ->
                debug = Base.Debug.event(debug, { :in, :die, elem(from, 0) })
                Base.reply(from, :ok)
                debug = Base.Debug.event(debug, { :out, :ok, elem(from, 0)  })
                terminate(count, parent, debug, :die)
            end
          end

          defp terminate(count, parent, debug, reason) do
            event = { :EXIT, reason }
            debug = Base.Debug.event(debug, event)
            Base.stop(__MODULE__, count, parent, debug, reason, event)
          end

        end

  """
    defmacro __using__(_options) do
    quote location: :keep do

      @behaviour Base.Sys
      require Base.Sys

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
