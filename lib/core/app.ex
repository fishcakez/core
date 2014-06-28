defmodule Core.App do
  @moduledoc false

  use Application

  def start(_type, _args) do
    Core.Debug.Supervisor.start_link()
  end

end
