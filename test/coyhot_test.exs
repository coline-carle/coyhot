defmodule CoyhotTest do
  use ExUnit.Case
  doctest Coyhot

  defmodule GenRelay do
    use GenServer

    def send_message(message) do
      GenServer.cast(__MODULE__, {:send_message, message})
    end

    def start_link(parent_pid) do
      GenServer.start_link(__MODULE__, parent_pid, name: __MODULE__)
    end

    def init(parent_pid) do
      {:ok, parent_pid}
    end

    def handle_cast({:send_message, message}, state) do
      parent_pid = state

      send(parent_pid, {:message, message})
      {:noreply, state}
    end
  end

  defmodule TickingCoyhot do
    use Coyhot
    require Logger

    @behaviour Coyhot

    def start_link(task_supervisor) do
      GenServer.start_link(__MODULE__, [task_supervisor, nil], name: SimpleCoyhot)
    end

    def tasks_data(_) do
      ["Task A", "Task B"]
    end

    def ticker(_) do
      GenRelay.send_message("tick")
      20
    end

    def handle_task(data, _) do
      GenRelay.send_message(data)
    end
  end

  test "coyhot when ticking" do
    {:ok, task_supervisor } = Task.Supervisor.start_link()
    {:ok, _gen_relay } = GenRelay.start_link(self())
    {:ok, _coyhot } = TickingCoyhot.start_link(task_supervisor)

    # coyhot does not ccrash so it ccan lunch again the task
    assert_receive {:message, "tick"}
    assert_receive {:message, "Task A"}
    assert_receive {:message, "Task B"}

    assert_receive {:message, "tick"}
    assert_receive {:message, "Task A"}
    assert_receive {:message, "Task B"}
  end

  defmodule SlowCoyhot do
    use Coyhot
    require Logger

    @behaviour Coyhot

    def start_link(task_supervisor) do
      GenServer.start_link(__MODULE__, [task_supervisor, nil], name:  __MODULE__)
    end

    def ticker(_) do
      GenRelay.send_message("tick")
      10
    end

    def tasks_data(_) do
      ["slow task"]
    end

    def handle_task(data, _) do
      GenRelay.send_message(data)
      :timer.sleep(15)
    end
  end

  test "test coyhot when task take longer than tick" do
    {:ok, task_supervisor } = Task.Supervisor.start_link()
    {:ok, _gen_relay } = GenRelay.start_link(self())
    {:ok, _coyhot } = SlowCoyhot.start_link(task_supervisor)

    assert_receive {:message, "tick"}
    assert_receive {:message, "slow task"}

    assert_receive {:message, "tick"}
    assert_receive {:message, "slow task"}
  end

  defmodule CrashingCoyhot do
    use Coyhot
    require Logger

    @behaviour Coyhot

    def start_link(task_supervisor) do
      GenServer.start_link(__MODULE__, [task_supervisor, nil], name:  __MODULE__)
    end

    def ticker(_) do
      5
    end

    def tasks_data(_) do
      ["before apocalypse"]
    end

    def handle_task(data, _) do
      GenRelay.send_message(data)
      raise "end of the world"
    end
  end

  test "test coyhot when task  are crashing" do
    {:ok, task_supervisor } = Task.Supervisor.start_link()
    {:ok, _gen_relay } = GenRelay.start_link(self())
    {:ok, _coyhot } = CrashingCoyhot.start_link(task_supervisor)
    assert_receive {:message, "before apocalypse"}
    assert_receive {:message, "before apocalypse"}
  end

end
