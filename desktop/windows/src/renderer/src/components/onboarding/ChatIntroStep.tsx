import { useState } from 'react'
import { Sparkles } from 'lucide-react'

type ChatIntroStepProps = {
  /** Complete onboarding and jump straight to chat (the /home hub). */
  onFinish: () => void
}

// Illustrative prompt suggestions shown on the onboarding completion screen —
// they demonstrate the kind of thing you can ask omi in chat (real answers draw
// on the conversations and context omi has gathered). Static: they set
// expectations for the chat surface the Finish button lands on.
const SAMPLE_PROMPTS = [
  'Summarize my last meeting',
  'What did I say I’d follow up on?',
  'Draft a reply to Alex'
]

function PromptChip({ text }: { text: string }): React.JSX.Element {
  return (
    <div className="flex w-full items-center gap-3 rounded-xl bg-white/[0.06] px-4 py-2.5 text-left">
      <span className="text-sm text-white/70">{text}</span>
    </div>
  )
}

export function ChatIntroStep({ onFinish }: ChatIntroStepProps): React.JSX.Element {
  // Terminal step: guard against a double-click firing completeOnboarding twice
  // (idempotent, but the second run is pure noise) — disable on the first click.
  const [finishing, setFinishing] = useState(false)

  return (
    <div className="animate-fade-in flex w-full max-w-[360px] flex-col items-center text-center">
      <div className="relative mb-6 flex h-24 w-24 items-center justify-center">
        {/* Soft radial glow behind the icon. */}
        <div className="absolute inset-0 rounded-full bg-white/[0.07] blur-2xl" />
        <div className="relative flex h-16 w-16 items-center justify-center rounded-3xl bg-white/[0.08]">
          <Sparkles className="h-8 w-8 text-white/85" />
        </div>
      </div>

      <h1 className="font-display text-3xl font-semibold text-white/95">Chat with omi</h1>
      <p className="mt-3 text-sm leading-relaxed text-white/50">
        Ask omi anything. It draws on your conversations and memory to answer, summarize, and take
        things off your plate.
      </p>

      <div className="mt-7 flex w-full flex-col gap-2">
        {SAMPLE_PROMPTS.map((p) => (
          <PromptChip key={p} text={p} />
        ))}
      </div>

      <button
        type="button"
        onClick={() => {
          if (finishing) return
          setFinishing(true)
          onFinish()
        }}
        disabled={finishing}
        className="mt-8 rounded-xl bg-white px-8 py-3 text-sm font-semibold text-black transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
      >
        Start chatting
      </button>
    </div>
  )
}
