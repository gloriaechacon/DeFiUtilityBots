"use client";

import styles from "./action-bar.module.css";
import { Button } from "./button";
import { useSimulation } from "../simulation/simulation-context";

export function ActionBar() {
  const { start, reset, state } = useSimulation();

  return (
    <div className={styles.actionBar}>
      <Button
        onClick={start}
        disabled={state.isRunning}
      >
        Start Session
      </Button>

      <Button onClick={reset}>
        Reset
      </Button>
    </div>
  );
}
