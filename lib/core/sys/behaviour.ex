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
            Core.start_link(__MODULE__, nil)
          end

          ## Core api

          def init(parent, _args) do
            Core.init_ack()
            loop(0, parent)
          end

          ## Core.Sys (minimal) api

          def system_continue(count, parent), do: loop(count, parent)

          def system_terminate(count, parent, reason) do
            terminate(count, parent, reason)
          end

          ## Internal

          defp loop(count, parent) do
            Core.Sys.receive(__MODULE__, count, parent) do
              { __MODULE__, from, :ping } ->
                Core.reply(from, :pong)
                loop(count + 1, parent)
              { __MODULE__, from, :count } ->
                Core.reply(from, count)
                loop(count, parent)
              { __MODULE__, from, :close } ->
                Core.reply(from, :ok)
                terminate(count, parent, :normal)
              { __MODULE__, from, :die } ->
                Core.reply(from, :ok)
                terminate(count, parent, :die)
            end
          end

          defp terminate(count, parent, reason) do
            event = { :EXIT, reason }
            Core.stop(__MODULE__, count, parent, reason, event)
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
