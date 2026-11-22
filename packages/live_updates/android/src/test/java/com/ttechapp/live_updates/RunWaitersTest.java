package com.ttechapp.live_updates;

import static org.junit.Assert.assertEquals;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.Test;

public class RunWaitersTest {
  private final List<String> finished = new ArrayList<>();
  private final RunWaiters<String> waiters = new RunWaiters<>(finished::add);

  @Test
  public void finishesOnlyThePressesARunTook() {
    waiters.add("first press", 1);
    waiters.add("late press", 2); // queued after the run's last take
    waiters.finishCovered(1); // the run ends and restarts for the late press
    assertEquals(Arrays.asList("first press"), finished);
    assertEquals(1, waiters.size());
    waiters.finishCovered(2); // the restarted run took it
    assertEquals(Arrays.asList("first press", "late press"), finished);
    assertEquals(0, waiters.size());
  }

  @Test
  public void aTimeoutFinishesEveryone() {
    waiters.add("a", 1);
    waiters.add("b", 5);
    waiters.finishAll();
    assertEquals(2, finished.size());
    assertEquals(0, waiters.size());
  }

  @Test
  public void nothingIsFinishedBeforeItsTake() {
    waiters.add("a", 3);
    waiters.finishCovered(2);
    assertEquals(0, finished.size());
  }
}
