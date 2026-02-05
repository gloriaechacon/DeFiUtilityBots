"use client";

import React, { createContext, useContext, useCallback, useMemo, useState, useEffect, useRef } from "react";
import type { SimulationMode, SimulationState, TimelineEvent } from "./types";

const initialState: SimulationState = {
  mode: "local",
  isRunning: false,
  flowState: "NEED_ACCESS",
  flowStartedAt: undefined,
  timeline: [],
  dashboardStats: {
    expenseVaultBalanceUsdc: 125.4,
    yieldEarnedUsdc: 0.38,
    paymentGateStatus: "None",
    lastPaymentTimestamp: undefined,
    lastPaymentAmountUsdc: undefined,
  },
};

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

function generateYieldFee(min: number, max: number) {
  return Math.random() * (max - min) + min;
}

function safeId() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : String(Date.now());
}

function addEvent(prev: TimelineEvent[], ev: Omit<TimelineEvent, "id" | "timestamp">): TimelineEvent[] {
  return [...prev, { id: safeId(), timestamp: Date.now(), ...ev }];
}

type SimulationContextValue = {
  state: SimulationState;
  setMode: (mode: SimulationMode) => void;
  start: () => Promise<void>;
  abort: (reason?: string) => void;
  reset: () => void;
  sessionDurationSec: number;
};

const SimulationContext = createContext<SimulationContextValue | null>(null);

export function SimulationProvider({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<SimulationState>(initialState);
  const yieldTimerRef = useRef<number | null>(null);

  useEffect(() => {
    if (yieldTimerRef.current) {
      window.clearInterval(yieldTimerRef.current);
      yieldTimerRef.current = null;
    }

    if (state.mode !== "local") return;

    yieldTimerRef.current = window.setInterval(() => {
      setState((s) => {
        if (s.dashboardStats.expenseVaultBalanceUsdc <= 0) return s;

        const fee = generateYieldFee(0.01, 0.06);

        return {
          ...s,
          dashboardStats: {
            ...s.dashboardStats,
            yieldEarnedUsdc: +(s.dashboardStats.yieldEarnedUsdc + fee).toFixed(2),
          },
        };
      });
    }, 12000);

    return () => {
      if (yieldTimerRef.current) {
        window.clearInterval(yieldTimerRef.current);
        yieldTimerRef.current = null;
      }
    };
  }, [state.mode]);

  const setMode = useCallback((mode: SimulationMode) => {
    setState((s) => ({ ...s, mode }));
  }, []);

  const reset = useCallback(() => {
    setState((s) => ({ ...initialState, mode: s.mode }));
  }, []);

  const abort = useCallback((reason?: string) => {
    setState((s) => ({
      ...s,
      flowState: "ABORTED",
      isRunning: false,
      timeline: addEvent(s.timeline, {
        type: "FLOW_ABORTED",
        title: "Flow Aborted",
        description: reason ?? "Simulation aborted manually",
        status: "error",
      }),
    }));
  }, []);

  const start = useCallback(async () => {
    setState((s) => ({
      ...s,
      isRunning: true,
      flowStartedAt: Date.now(),
      flowState: "NEED_ACCESS",
      timeline: [],
      dashboardStats: { ...s.dashboardStats, paymentGateStatus: "None" },
    }));

    setState((s) => ({
      ...s,
      timeline: addEvent(s.timeline, {
        type: "QUOTE_REQUESTED",
        title: "Service Quote Requested",
        description: "Agent requested a quote for a protected service",
        status: "info",
      }),
    }));

    await wait(900);

    setState((s) => ({
      ...s,
      flowState: "AWAITING_AUTHORIZATION",
      timeline: addEvent(s.timeline, {
        type: "PAYMENT_REQUIRED_402",
        title: "Micropayment Required",
        description: "Service enforced a payment gate before granting access",
        status: "warning",
        meta: { Gate: "0x402" },
      }),
    }));

    await wait(1100);

    setState((s) => ({
      ...s,
      flowState: "AUTHORIZATION_CONFIRMED",
      dashboardStats: { ...s.dashboardStats, paymentGateStatus: "Verified" },
      timeline: addEvent(s.timeline, {
        type: "ACCESS_GRANTED",
        title: "Access Granted",
        description: "Payment verified; access authorized",
        status: "success",
      }),
    }));

    await wait(1000);

    setState((s) => ({
      ...s,
      flowState: "ACCESSING_RESOURCE",
      timeline: addEvent(s.timeline, {
        type: "RESOURCE_ACCESS_STARTED",
        title: "Resource Access Started",
        description: "Autonomous session started",
        status: "info",
      }),
    }));

    await wait(1200);

    setState((s) => ({
      ...s,
      flowState: "COMPLETED",
      isRunning: false,
      dashboardStats: {
        ...s.dashboardStats,
        lastPaymentAmountUsdc: 12,
        lastPaymentTimestamp: Date.now(),
        expenseVaultBalanceUsdc: +(s.dashboardStats.expenseVaultBalanceUsdc - 12).toFixed(2),
      },
      timeline: addEvent(s.timeline, {
        type: "SERVICE_FULFILLED",
        title: "Service Fulfilled",
        description: "Autonomous payment + access completed successfully",
        status: "success",
      }),
    }));
  }, []);

  const sessionDurationSec = state.flowStartedAt ? Math.floor((Date.now() - state.flowStartedAt) / 1000) : 0;

  const value = useMemo(
    () => ({ state, setMode, start, abort, reset, sessionDurationSec }),
    [state, setMode, start, abort, reset, sessionDurationSec]
  );

  return <SimulationContext.Provider value={value}>{children}</SimulationContext.Provider>;
}

export function useSimulation() {
  const ctx = useContext(SimulationContext);
  if (!ctx) throw new Error("useSimulation must be used inside <SimulationProvider />");
  return ctx;
}