"use client";

import styles from "./controls-bar.module.css";
import { ToggleOption } from "./toggle-option";
import { useSimulation } from "../simulation/simulation-context";
import { ConnectButton } from "@rainbow-me/rainbowkit";

export function ControlsBar() {
    const { state, setMode, start, reset } = useSimulation();
    const isLocal = state.mode === "local";

    return (
        <div className={styles.controls}>
            <div className={styles.mode}>
                <ToggleOption
                    label={`Local Simulation: ${isLocal ? "ON" : "OFF"}`}
                    active={isLocal}
                    onClick={() => setMode(isLocal ? "testnet" : "local")}
                />
            </div>
            <ConnectButton />
        </div>
    )
}