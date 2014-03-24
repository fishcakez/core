defmodule Base.App do
  use Application.Behaviour

  def start(_type, _args) do
    Base.Debug.Supervisor.start_link()
  end

end
