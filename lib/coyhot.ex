defmodule Coyhot do

  @doc """
  determine how much time is necessary between tasks
  """
  @callback ticker() :: integer


  @doc """
  task function name
  """
  @callback handle_task(arg :: term) :: :noreply

  @doc """
  function that fetch data to process for each tasks
  """
  @callback tasks_data() :: List

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Coyhot

      use GenServer

      def handle_task(_) do
        raise "attempt to call handle_task(data) but clause was not provided"
      end

      def tasks_data() do
        raise "attempt to call tasks_data() but clause was not provided"
      end

      def ticker() do
        raise "attempt to call ticker() but clause was not provided"
      end

      def tasks_done(result) do
        :noop
      end


      def init([task_supervisor, use_ticker, timeout]) do
        state =
          %{
            timeout_ref: make_ref(),
            task_supervisor: task_supervisor,
            tasks: [],
            timeout: timeout,
            timer: nil,
            use_ticker: use_ticker
          }
          |> schedule_tasks

        {:ok, state}
      end

      def handle_info({:timeout, timeout_ref}, %{timeout_ref: timeout_ref} = state) do
        %{state | timer: nil}
        |> schedule_tasks
        {:noreply, state}
      end

      def handle_info({:DOWN, mref, _, _pid, _reason}, %{tasks: tasks} = state) do
        state = state |> handle_task_finished(mref)
        {:noreply, state}
      end

      def handle_info({task_ref, result}, state) when is_reference(task_ref) do
        state = state |> handle_task_finished(task_ref)
        {:noreply, state}
      end

      def handle_info(:ticker, state) do
        state =
          state
          |> cancel_timer
          |> schedule_tasks
        {:noreply, state}
      end

      def handle_task_finished(state, ref) do
        state
        |> remove_task(ref)
        |> cancel_timer_if_done
        |> schedule_if_done
      end

      defp schedule_tasks(state) do
        state
        |> start_tasks()
        |> start_timer()
        |> start_ticking()
      end

      defp start_tasks(%{task_supervisor: supervisor} = state) do
        tasks = tasks_data()
               |> Enum.map(&start_task(supervisor, &1))
               |> Enum.map(fn(task) -> task.ref end)
        %{state | tasks: tasks}
      end

      defp start_task(task_supervisor, data) do
        Task.Supervisor.async_nolink(
          task_supervisor, fn() ->
            handle_task(data)
          end
        )
      end

      defp start_ticking(%{use_ticker: true} = state) do
        next_tick = ticker()
        Process.send_after(self(), :ticker, next_tick)
        state
      end
      defp start_ticking(state), do: state

      defp setup_timer(%{timeout: :inifniy} = state), do: state
      defp start_timer(%{timeout_ref: timeout_ref, timeout: timeout} = state) do
        %{state | timer: Process.send_after(self(), {:timeout, timeout_ref}, timeout)}
      end

      defp remove_task(%{tasks: tasks} = state, task_ref) do
        %{state | tasks: tasks |> List.delete(task_ref)}
      end

      defp schedule_if_done(%{tasks: [], use_ticker: false} = state) do
        state |> schedule_tasks
      end
      defp schedule_if_done(state), do: state

      defp cancel_timer_if_done(%{tasks: []} = state) do
        state |> cancel_timer
      end
      defp cancel_timer_if_done(state), do: state

      defp cancel_timer(%{timer: nil} = state), do: state
      defp cancel_timer(%{timer: timer, timeout_ref: timeout_ref} = state) do
        :erlang.cancel_timer(timer)
        receive do
          {:timeout, ^timeout_ref} -> :ok
        after 0 -> :ok
        end
        %{state | timer: nil}
      end

      defoverridable [handle_task: 1, tasks_data: 0, ticker: 0]
    end
  end
end
