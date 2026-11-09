using DiscordClone.Bridge;
using Microsoft.UI.Dispatching;

namespace DiscordClone.Windows.ViewModels;

/// The relay owns nothing but a dispatcher hop. It holds no reference to the client or the
/// ViewModel, so a stale subscription cannot resurrect a closed session (docs/ffi-contract.md).
internal sealed class EventRelay : ChatEventListener
{
    private readonly DispatcherQueue _queue;
    private readonly Action<ChatEvent> _deliver;

    public EventRelay(DispatcherQueue queue, Action<ChatEvent> deliver)
    {
        _queue = queue;
        _deliver = deliver;
    }

    // Rust calls this from its Tokio worker, never from the UI thread.
    public void OnEvent(ChatEvent payload)
    {
        _queue.TryEnqueue(() => _deliver(payload));
    }
}
