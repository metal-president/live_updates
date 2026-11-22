package com.ttechapp.live_updates;

import java.util.ArrayList;
import java.util.List;

/**
 * Callers (broadcast receivers) waiting for background runs, each with the
 * take count that covers its press: the press is handled once the background
 * handler has taken queued presses that many times.
 */
final class RunWaiters<T> {
  interface Finisher<T> {
    void finish(T waiter);
  }

  private final List<T> waiters = new ArrayList<>();
  private final List<Integer> takes = new ArrayList<>();
  private final Finisher<T> finisher;

  RunWaiters(Finisher<T> finisher) {
    this.finisher = finisher;
  }

  /** Adds a waiter whose press is covered by take number {@code take}. */
  void add(T waiter, int take) {
    waiters.add(waiter);
    takes.add(take);
  }

  /** Finishes the waiters whose presses were taken by take {@code covered} or earlier. */
  void finishCovered(int covered) {
    for (int i = waiters.size() - 1; i >= 0; i--) {
      if (takes.get(i) <= covered) {
        finisher.finish(waiters.remove(i));
        takes.remove(i);
      }
    }
  }

  /** Finishes every waiter. */
  void finishAll() {
    finishCovered(Integer.MAX_VALUE);
  }

  int size() {
    return waiters.size();
  }
}
