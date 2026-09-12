#!/usr/bin/env python3
"""Read-only replica of the v4 historical route pipeline with stage diagnostics.

This script never writes HealthKit and never mutates the incident snapshot. It mirrors
HistoricalHealthKitRepairV4.swift closely enough to show where points disappear and
which long ACTIVE gaps are already present in raw data versus introduced by filtering.
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True)
class Point:
    timestamp: float
    latitude: float
    longitude: float
    altitude: float
    horizontal_accuracy: float
    vertical_accuracy: float
    native_speed: float | None
    cumulative_distance: float | None
    source: str


@dataclass(frozen=True)
class Stage:
    name: str
    points: tuple[Point, ...]
    geometry_m: float
    active_gaps_gt3: int
    max_active_gap_s: float


def number(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def parse_date(value: Any) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        raise ValueError(f"unsupported date value: {value!r}")
    return datetime.fromisoformat(value.strip().replace("Z", "+00:00")).timestamp()


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).isoformat(timespec="milliseconds")


def find_session_dir(root: Path, session_id: str) -> Path:
    direct = root / session_id
    if (direct / "summary.json").is_file() and (direct / "samples.jsonl").is_file():
        return direct
    candidates: list[Path] = []
    for summary in root.rglob("summary.json"):
        parent = summary.parent
        if parent.name == session_id and (parent / "samples.jsonl").is_file():
            candidates.append(parent)
    if not candidates:
        raise FileNotFoundError(
            f"session {session_id} introuvable sous {root} (summary.json + samples.jsonl)"
        )
    if len(candidates) > 1:
        print("ATTENTION: plusieurs copies trouvées; première utilisée:")
        for item in candidates:
            print(f" - {item}")
    return candidates[0]


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    result: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_no, line in enumerate(handle, 1):
            text = line.strip()
            if not text:
                continue
            try:
                obj = json.loads(text)
            except json.JSONDecodeError as exc:
                print(f"WARN {path.name}:{line_no}: JSON invalide: {exc}")
                continue
            if isinstance(obj, dict):
                result.append(obj)
    return result


def point_from_row(row: dict[str, Any], start: float, end: float) -> Point | None:
    ts = number(row.get("timestamp"))
    if ts is None or ts < start or ts > end or row.get("record") != "sample":
        return None
    kind = str(row.get("kind") or "")
    payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
    quality = row.get("quality") if isinstance(row.get("quality"), dict) else {}
    lat = number(payload.get("latitude"))
    lon = number(payload.get("longitude"))
    if lat is None or lon is None or not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None

    if kind == "watch_location":
        source = "WATCH"
        horizontal = number(payload.get("horizontal_accuracy_m"))
        vertical = number(payload.get("vertical_accuracy_m"))
        speed = number(payload.get("native_speed_mps"))
        if speed is None:
            speed = number(payload.get("speed_mps"))
    elif kind == "location":
        source = "IPHONE"
        horizontal = number(quality.get("horizontal_accuracy_m"))
        vertical = number(quality.get("vertical_accuracy_m"))
        speed = number(quality.get("native_speed_mps"))
        if speed is None:
            speed = number(payload.get("speed_mps"))
    else:
        return None

    if horizontal is None or horizontal < 0 or horizontal > 50:
        return None

    return Point(
        timestamp=ts,
        latitude=lat,
        longitude=lon,
        altitude=number(payload.get("altitude_m")) or 0.0,
        horizontal_accuracy=horizontal,
        vertical_accuracy=vertical if vertical is not None else -1.0,
        native_speed=speed,
        cumulative_distance=number(payload.get("distance_m")),
        source=source,
    )


def haversine_m(a: Point, b: Point) -> float:
    radius = 6_371_000.0
    lat1 = math.radians(a.latitude)
    lat2 = math.radians(b.latitude)
    dlat = lat2 - lat1
    dlon = math.radians(b.longitude - a.longitude)
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * radius * math.asin(min(1.0, math.sqrt(h)))


def implied_speed(a: Point, b: Point) -> float:
    dt = b.timestamp - a.timestamp
    return math.inf if dt <= 0 else haversine_m(a, b) / dt


def deduplicate(points: Iterable[Point]) -> list[Point]:
    seen: set[str] = set()
    result: list[Point] = []
    for point in sorted(points, key=lambda item: item.timestamp):
        key = f"{point.timestamp:.3f}|{point.latitude:.6f}|{point.longitude:.6f}"
        if key in seen:
            continue
        seen.add(key)
        result.append(point)
    return result


def in_pause(ts: float, pauses: list[tuple[float, float]]) -> bool:
    return any(start <= ts <= end for start, end in pauses)


def interval_overlaps_pause(start: float, end: float, pauses: list[tuple[float, float]]) -> bool:
    return any(start <= pause_end and end >= pause_start for pause_start, pause_end in pauses)


def make_pauses(rows: Iterable[dict[str, Any]], start: float, end: float) -> list[tuple[float, float]]:
    explicit: list[tuple[float, bool]] = []
    fallback: list[tuple[float, str, str]] = []
    for row in rows:
        ts = number(row.get("timestamp"))
        if ts is None or ts < start or ts > end or row.get("record") != "event" or row.get("source") != "watch":
            continue
        event = str(row.get("event") or "")
        payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
        if event in {"manual_pause", "auto_pause"}:
            explicit.append((ts, True))
        elif event in {"manual_resume", "auto_resume"}:
            explicit.append((ts, False))
        elif event == "phase_changed":
            src = payload.get("from")
            dst = payload.get("to")
            if isinstance(src, str) and isinstance(dst, str):
                fallback.append((ts, src, dst))

    marks = sorted(explicit)
    if not any(is_pause for _, is_pause in marks):
        marks = []
        for ts, src, dst in sorted(fallback):
            if src == "active" and dst == "paused":
                marks.append((ts, True))
            elif src == "paused" and dst == "active":
                marks.append((ts, False))
            elif src == "paused" and dst == "ended":
                marks.append((min(ts, end), False))

    result: list[tuple[float, float]] = []
    opened: float | None = None
    for raw_ts, pause in marks:
        ts = min(max(raw_ts, start), end)
        if pause:
            if opened is None:
                opened = ts
        elif opened is not None and ts > opened:
            result.append((opened, ts))
            opened = None
    if opened is not None and end > opened:
        result.append((opened, end))
    return result


def make_stage(name: str, points: Iterable[Point], pauses: list[tuple[float, float]]) -> Stage:
    ordered = deduplicate(points)
    active_pairs = [
        (a, b)
        for a, b in zip(ordered, ordered[1:])
        if not interval_overlaps_pause(a.timestamp, b.timestamp, pauses)
    ]
    geometry = sum(haversine_m(a, b) for a, b in active_pairs)
    gaps = [b.timestamp - a.timestamp for a, b in active_pairs if b.timestamp > a.timestamp]
    return Stage(
        name=name,
        points=tuple(ordered),
        geometry_m=geometry,
        active_gaps_gt3=sum(gap > 3.0 for gap in gaps),
        max_active_gap_s=max(gaps, default=0.0),
    )


def perpendicular_deviation(point: Point, start: Point, end: Point) -> float:
    a = haversine_m(start, point)
    b = haversine_m(point, end)
    c = haversine_m(start, end)
    if c <= 0.5:
        return min(a, b)
    s = (a + b + c) / 2
    area2 = max(0.0, s * (s - a) * (s - b) * (s - c))
    return 2 * math.sqrt(area2) / c


def counter_aware_filter(points: list[Point]) -> list[Point]:
    if len(points) < 3:
        return points[:]
    accepted = [points[0]]
    for point in points[1:]:
        last = accepted[-1]
        dt = point.timestamp - last.timestamp
        if dt <= 0:
            continue
        previous_distance = last.cumulative_distance
        current_distance = point.cumulative_distance
        if previous_distance is None or current_distance is None or current_distance < previous_distance:
            accepted.append(point)
            continue
        raw_delta = current_distance - previous_distance
        geometry_delta = haversine_m(last, point)
        accuracy_budget = min(40.0, max(8.0, last.horizontal_accuracy + point.horizontal_accuracy))
        if dt <= 10 and geometry_delta > raw_delta * 2.5 + accuracy_budget:
            continue
        if dt <= 3.5 and raw_delta < 0.75 and geometry_delta <= accuracy_budget:
            continue
        accepted.append(point)
    if points and accepted[-1].timestamp != points[-1].timestamp:
        accepted.append(points[-1])
    return deduplicate(accepted)


def denoise_for_distance(
    points: list[Point],
    target_distance: float,
    pauses: list[tuple[float, float]],
    speed_limit: float,
) -> list[Point]:
    current = make_stage("denoise-work", points, pauses)
    if target_distance <= 100 or len(points) < 3:
        return list(current.points)
    upper_target = target_distance + max(120.0, target_distance * 0.10)
    if current.geometry_m <= upper_target:
        return list(current.points)

    values = list(current.points)
    limit = speed_limit * 1.15
    while current.geometry_m > upper_target and len(values) >= 3:
        best_index: int | None = None
        best_reduction = 0.0
        for index in range(1, len(values) - 1):
            previous = values[index - 1]
            point = values[index]
            nxt = values[index + 1]
            if nxt.timestamp - previous.timestamp > 4.25:
                continue
            if interval_overlaps_pause(previous.timestamp, nxt.timestamp, pauses):
                continue
            if implied_speed(previous, nxt) > limit:
                continue
            before = haversine_m(previous, point) + haversine_m(point, nxt)
            after = haversine_m(previous, nxt)
            reduction = before - after
            if reduction <= 0.25:
                continue
            deviation = perpendicular_deviation(point, previous, nxt)
            noise_envelope = min(30.0, max(6.0, point.horizontal_accuracy * 1.5))
            if deviation > noise_envelope:
                continue
            if reduction > best_reduction:
                best_reduction = reduction
                best_index = index
        if best_index is None:
            break
        values.pop(best_index)
        current = make_stage("denoise-work", values, pauses)
    return values


def sanitize(
    source: str,
    points: list[Point],
    pauses: list[tuple[float, float]],
    target_distance: float | None,
    speed_limit: float,
) -> list[Stage]:
    stages: list[Stage] = []
    raw = deduplicate(points)
    stages.append(make_stage("raw", raw, pauses))

    values = [point for point in raw if not in_pause(point.timestamp, pauses)]
    stages.append(make_stage("after_pause", values, pauses))

    changed = True
    while changed and len(values) >= 3:
        changed = False
        next_values = [values[0]]
        for index in range(1, len(values) - 1):
            previous = next_values[-1] if next_values else values[index - 1]
            current = values[index]
            nxt = values[index + 1]
            if (
                implied_speed(previous, current) > speed_limit
                and implied_speed(current, nxt) > speed_limit
                and implied_speed(previous, nxt) <= speed_limit
            ):
                changed = True
                continue
            next_values.append(current)
        next_values.append(values[-1])
        values = next_values
    stages.append(make_stage("after_spike", values, pauses))

    accepted: list[Point] = []
    for point in values:
        if not accepted:
            accepted.append(point)
            continue
        last = accepted[-1]
        if interval_overlaps_pause(last.timestamp, point.timestamp, pauses) or implied_speed(last, point) <= speed_limit:
            accepted.append(point)
    stages.append(make_stage("after_sequential", accepted, pauses))

    if target_distance is not None:
        accepted = counter_aware_filter(accepted)
    stages.append(make_stage("after_counter", accepted, pauses))

    if target_distance is not None:
        accepted = denoise_for_distance(accepted, target_distance, pauses, speed_limit)
    stages.append(make_stage("after_denoise", accepted, pauses))
    return stages


def counter_agrees(summary_m: float, raw_m: float | None) -> bool:
    if summary_m <= 100 or raw_m is None or raw_m <= 100:
        return False
    tolerance = max(150.0, summary_m * 0.12)
    return abs(raw_m - summary_m) <= tolerance


def merge_active_gaps(
    primary: list[Point],
    secondary: list[Point],
    pauses: list[tuple[float, float]],
    speed_limit: float,
) -> list[Point]:
    if len(primary) < 2 or len(secondary) < 2:
        return primary[:]
    limit = speed_limit * 1.15
    primary = sorted(primary, key=lambda point: point.timestamp)
    secondary = sorted(secondary, key=lambda point: point.timestamp)
    merged: list[Point] = []
    for index in range(len(primary) - 1):
        start = primary[index]
        end = primary[index + 1]
        if not merged or merged[-1].timestamp != start.timestamp:
            merged.append(start)
        gap = end.timestamp - start.timestamp
        if gap <= 3 or interval_overlaps_pause(start.timestamp, end.timestamp, pauses):
            continue
        candidates = [
            point
            for point in secondary
            if start.timestamp < point.timestamp < end.timestamp
            and point.horizontal_accuracy <= 35
            and not in_pause(point.timestamp, pauses)
        ]
        if not candidates:
            continue
        bridge: list[Point] = []
        previous = start
        for candidate in candidates:
            if implied_speed(previous, candidate) <= limit:
                bridge.append(candidate)
                previous = candidate
        while bridge and implied_speed(bridge[-1], end) > limit:
            bridge.pop()
        if not bridge or implied_speed(bridge[-1], end) > limit:
            continue
        merged.extend(bridge)
    if primary:
        merged.append(primary[-1])
    return deduplicate(merged)


def print_stage(source: str, stage: Stage) -> None:
    print(
        f"{source:6s} {stage.name:17s} "
        f"points={len(stage.points):4d} geom={stage.geometry_m:8.1f}m "
        f"gaps>3={stage.active_gaps_gt3:3d} max={stage.max_active_gap_s:7.2f}s"
    )


def top_active_gaps(points: Iterable[Point], pauses: list[tuple[float, float]], limit: int = 12) -> list[tuple[float, Point, Point]]:
    ordered = deduplicate(points)
    result: list[tuple[float, Point, Point]] = []
    for a, b in zip(ordered, ordered[1:]):
        gap = b.timestamp - a.timestamp
        if gap <= 3 or interval_overlaps_pause(a.timestamp, b.timestamp, pauses):
            continue
        result.append((gap, a, b))
    result.sort(key=lambda item: item[0], reverse=True)
    return result[:limit]


def count_between(points: Iterable[Point], start: float, end: float) -> int:
    return sum(start < point.timestamp < end for point in points)


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only v4 historical route pipeline diagnostic")
    parser.add_argument("--root", required=True, help="Racine du snapshot incident gelé")
    parser.add_argument("--session", required=True, help="Session ID Tracker")
    args = parser.parse_args()

    session_dir = find_session_dir(Path(args.root), args.session)
    summary = json.loads((session_dir / "summary.json").read_text(encoding="utf-8"))
    start = parse_date(summary["startedAt"])
    end = parse_date(summary["endedAt"])
    summary_distance = float(summary.get("distanceMeters") or 0.0)

    rows = load_jsonl(session_dir / "samples.jsonl")
    reliable = session_dir / "watch_reliable.jsonl"
    if reliable.is_file():
        rows.extend(load_jsonl(reliable))

    watch: list[Point] = []
    phone: list[Point] = []
    watch_distances: list[tuple[float, float]] = []
    phone_distances: list[tuple[float, float]] = []
    for row in rows:
        point = point_from_row(row, start, end)
        if point is not None:
            (watch if point.source == "WATCH" else phone).append(point)
        if row.get("record") == "sample":
            ts = number(row.get("timestamp"))
            payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
            distance = number(payload.get("distance_m"))
            if ts is not None and start <= ts <= end and distance is not None and distance >= 0:
                if row.get("kind") == "watch_location":
                    watch_distances.append((ts, distance))
                elif row.get("kind") == "location":
                    phone_distances.append((ts, distance))

    pauses = make_pauses(rows, start, end)
    watch_distance = sorted(watch_distances)[-1][1] if watch_distances else None
    phone_distance = sorted(phone_distances)[-1][1] if phone_distances else None
    watch_trusted = counter_agrees(summary_distance, watch_distance)
    phone_trusted = counter_agrees(summary_distance, phone_distance)
    speed_limit = 25.0  # .other inspection and cycling both use 25 m/s in current v4

    watch_stages = sanitize("WATCH", watch, pauses, summary_distance if watch_trusted else None, speed_limit)
    phone_stages = sanitize("IPHONE", phone, pauses, summary_distance if phone_trusted else None, speed_limit)

    watch_final = list(watch_stages[-1].points)
    phone_final = list(phone_stages[-1].points)
    if watch_trusted and not phone_trusted:
        primary_name, primary, secondary = "WATCH", watch_final, phone_final
    elif phone_trusted and not watch_trusted:
        primary_name, primary, secondary = "IPHONE", phone_final, watch_final
    else:
        # This incident has a trusted Watch counter; fallback kept deterministic only for general use.
        primary_name, primary, secondary = ("WATCH", watch_final, phone_final) if len(watch_final) >= len(phone_final) else ("IPHONE", phone_final, watch_final)

    fused = merge_active_gaps(primary, secondary, pauses, speed_limit)
    final = denoise_for_distance(fused, summary_distance, pauses, speed_limit)
    fused_stage = make_stage("fusion", fused, pauses)
    final_stage = make_stage("final_denoise", final, pauses)

    pause_total = sum(max(0.0, b - a) for a, b in pauses)
    print("TRACKER HISTORICAL ROUTE PIPELINE — READ ONLY")
    print(f"session               : {args.session}")
    print(f"source dir            : {session_dir}")
    print(f"start UTC             : {iso(start)}")
    print(f"end UTC               : {iso(end)}")
    print(f"wall duration         : {end - start:.3f}s")
    print(f"summary distance      : {summary_distance:.3f}m")
    print(f"pauses                : {len(pauses)} / {pause_total:.3f}s")
    print(f"watch raw counter     : {watch_distance}")
    print(f"iphone raw counter    : {phone_distance}")
    print(f"trusted               : WATCH={watch_trusted} IPHONE={phone_trusted}")

    print("\n=== PIPELINE COUNTS / GEOMETRY ===")
    for stage in watch_stages:
        print_stage("WATCH", stage)
    for stage in phone_stages:
        print_stage("IPHONE", stage)
    print_stage("FUSED", fused_stage)
    print_stage("FINAL", final_stage)
    print(f"primary               : {primary_name}")

    print("\n=== TOP ACTIVE GAPS IN FINAL ROUTE ===")
    raw_watch = deduplicate(watch)
    raw_phone = deduplicate(phone)
    for rank, (gap, a, b) in enumerate(top_active_gaps(final, pauses), 1):
        print(
            f"#{rank:02d} gap={gap:8.3f}s {iso(a.timestamp)} -> {iso(b.timestamp)} "
            f"src={a.source}->{b.source} "
            f"raw_inside WATCH={count_between(raw_watch, a.timestamp, b.timestamp)} "
            f"IPHONE={count_between(raw_phone, a.timestamp, b.timestamp)}"
        )

    print("\n=== TOP ACTIVE GAPS IN RAW WATCH ===")
    for rank, (gap, a, b) in enumerate(top_active_gaps(raw_watch, pauses), 1):
        print(
            f"#{rank:02d} gap={gap:8.3f}s {iso(a.timestamp)} -> {iso(b.timestamp)} "
            f"iphone_raw_inside={count_between(raw_phone, a.timestamp, b.timestamp)}"
        )

    print("\n=== PAUSE WINDOWS ===")
    for index, (pause_start, pause_end) in enumerate(pauses, 1):
        print(
            f"#{index:02d} {iso(pause_start)} -> {iso(pause_end)} "
            f"duration={pause_end - pause_start:.3f}s"
        )

    print("\nINTERPRETATION")
    print("- If a long FINAL gap also exists in RAW WATCH with no/low iPhone coverage, it is a real capture hole.")
    print("- If RAW WATCH is continuous but a later stage creates the gap, the filter stage is the root cause.")
    print("- No HealthKit write or incident-file mutation is performed by this script.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
