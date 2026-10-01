'use client';
/**
 * Focusable tooltip trigger for status pills (frontend review M-9, Design §6 "badge text + dot +
 * tooltip"): the explanation is shown on hover *and* keyboard focus (Radix tooltip), and is part of
 * the accessible description for screen readers (sr-only text), instead of a `title` attribute
 * that keyboard, touch and many screen-reader users never get.
 */
import { SimpleTooltip } from '@/components/ui/tooltip';

export function Hint({ content, children }: { content: string; children: React.ReactNode }) {
  return (
    <SimpleTooltip content={content}>
      <span
        tabIndex={0}
        className="inline-flex rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-1"
      >
        {children}
        <span className="sr-only">: {content}</span>
      </span>
    </SimpleTooltip>
  );
}
