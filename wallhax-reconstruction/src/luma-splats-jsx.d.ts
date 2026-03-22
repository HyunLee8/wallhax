import 'react'

/* R3F `extend({ LumaSplats: LumaSplatsThree })` — JSX needs this intrinsic. */
declare module 'react' {
  namespace JSX {
    interface IntrinsicElements {
      lumaSplats: Record<string, unknown>
    }
  }
}
