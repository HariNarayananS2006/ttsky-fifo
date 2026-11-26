# SPDX-FileCopyrightText: © 2026 S Harinarayanan
# SPDX-License-Identifier: Apache-2.0
#
# Tests for the 8 x 16 FIFO. Only top-level pins are used, so the same test
# runs on the RTL and on the gate-level netlist (GL test).
#
# Pins: ui_in = din, uio_in[0] = wr_en, uio_in[1] = rd_en,
#       uo_out = dout, uio_out[2] = full, uio_out[3] = empty.
# Inputs are changed on the falling edge and outputs are checked on the
# falling edge, i.e. half a cycle after the rising edge that updated them.

import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

DEPTH = 16
WR = 0x01
RD = 0x02


def flags(dut):
    v = int(dut.uio_out.value)
    return (v >> 2) & 1, (v >> 3) & 1  # full, empty


async def reset(dut):
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    # reset is released through a 2-flop synchronizer
    await ClockCycles(dut.clk, 3)
    await FallingEdge(dut.clk)


async def step(dut, wr=False, rd=False, din=0):
    """Apply inputs for one clock cycle, return after the next falling edge."""
    dut.ui_in.value = din
    dut.uio_in.value = (WR if wr else 0) | (RD if rd else 0)
    await FallingEdge(dut.clk)


@cocotb.test()
async def test_fill_and_drain(dut):
    await reset(dut)

    assert int(dut.uio_oe.value) == 0b0000_1100
    assert flags(dut) == (0, 1), "after reset: expected full=0, empty=1"
    assert int(dut.uo_out.value) == 0

    data = [(0xA5 + 37 * i) & 0xFF for i in range(DEPTH)]

    # Fill completely
    for i, d in enumerate(data):
        await step(dut, wr=True, din=d)
        full, empty = flags(dut)
        assert empty == 0
        assert full == (1 if i == DEPTH - 1 else 0), f"full wrong after write {i}"

    # Write while full is ignored
    await step(dut, wr=True, din=0x00)
    assert flags(dut) == (1, 0)

    # Drain completely; dout shows each word after its read is accepted
    for i, d in enumerate(data):
        await step(dut, rd=True)
        got = int(dut.uo_out.value)
        assert got == d, f"read {i}: got {got:#04x}, expected {d:#04x}"
        full, empty = flags(dut)
        assert full == 0
        assert empty == (1 if i == DEPTH - 1 else 0), f"empty wrong after read {i}"

    # Read while empty is ignored, dout holds the last value
    await step(dut, rd=True)
    assert flags(dut) == (0, 1)
    assert int(dut.uo_out.value) == data[-1]


@cocotb.test()
async def test_random_vs_model(dut):
    await reset(dut)
    random.seed(1234)

    q = deque()
    dout = 0
    for cyc in range(2000):
        # alternate write-heavy and read-heavy phases so the FIFO keeps
        # hitting both full and empty
        p_wr = 0.75 if (cyc // 200) % 2 == 0 else 0.25
        wr = random.random() < p_wr
        rd = random.random() < 1.0 - p_wr
        din = random.randrange(256)

        # reference model, using the state before the clock edge
        push = wr and len(q) < DEPTH
        pop = rd and len(q) > 0
        if pop:
            dout = q.popleft()
        if push:
            q.append(din)

        await step(dut, wr=wr, rd=rd, din=din)

        full, empty = flags(dut)
        assert full == (1 if len(q) == DEPTH else 0), f"cycle {cyc}: full={full}, count={len(q)}"
        assert empty == (1 if len(q) == 0 else 0), f"cycle {cyc}: empty={empty}, count={len(q)}"
        assert int(dut.uo_out.value) == dout, f"cycle {cyc}: dout={int(dut.uo_out.value):#04x}, expected {dout:#04x}"
