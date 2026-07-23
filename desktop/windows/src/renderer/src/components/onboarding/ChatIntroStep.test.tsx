// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from 'vitest'
import { render, cleanup, fireEvent, screen } from '@testing-library/react'
import { ChatIntroStep } from './ChatIntroStep'

afterEach(cleanup)

describe('ChatIntroStep', () => {
  it('completes onboarding once, even when the button is double-clicked', () => {
    const onFinish = vi.fn()
    render(<ChatIntroStep onFinish={onFinish} />)

    const button = screen.getByText('Start chatting')
    fireEvent.click(button)
    fireEvent.click(button)

    expect(onFinish).toHaveBeenCalledTimes(1)
  })
})
