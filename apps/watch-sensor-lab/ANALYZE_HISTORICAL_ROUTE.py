#!/usr/bin/env python3
"""Read-only audit of Tracker raw GPS for historical HealthKit reconstruction.

The script never writes HealthKit and never modifies the incident snapshot. It compares
Watch and iPhone GPS streams, pause coverage and timestamp spacing so we can choose a
route source based on evidence instead of point count alone.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
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
    speed: float | None
    source: str


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
    text = value.strip().replace("Z", "+00:00")
    return datetime.fromisoformat(text).timestamp()


def find_session_dir(root: Path, session_id: str) -> Path:
    direct = root / session_id
    if (direct / "summary.json").is_file() and (direct / "samples.jsonl").is_file():
        return direct
    candidates = []
    for summary in root.rglob("summary.json"):
        parent = summary.parent
        if parent.name == session_id and (parent / "samples.jsonl").is_file():
            candidates.append(parent)
    if not candidates:
        raise FileNotFoundError(
            f"session {session_id} introuvable sous {root} (summary.json + samples.jsonl)"
        )
    if len(candidates) > 1:
        print("ATTENTION: plusieurs copies de session trouvées; analyse de la première:")
        for candidate in candidates:
            print(f" - {candidate}")
    return candidates[0]


def load_jsonl(path: Path) -> Iterable[dict[str, Any]]:
    if not path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                print(f"WARN {path.name}:{line_number}: JSON invalide: {exc}")
                continue
            if isinstance(obj, dict):
                rows.append(obj)
    return rows


def point_from_row(row: dict[str, Any]) -> Point | None:
    if row.get("record") != "sample":
        return None
    kind = row.get("kind") or ""
    payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
    quality = row.get("quality") if isinstance(row.get("quality"), dict) else {}
    ts = number(row.get("timestamp"))
    lat = number(payload.get("latitude"))
    lon = number(payload.get("longitude"))
    if ts is None or lat is None or lon is None:
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None

    if kind == "watch_location":
        horizontal = number(payload.get("horizontal_accuracy_m"))
        vertical = number(payload.get("vertical_accuracy_m"))
        speed = number(payload.get("native_speed_mps"))
        if speed is None:
            speed = number(payload.get("speed_mps"))
        source = "watch"
    elif kind == "location":
        horizontal = number(quality.get("horizontal_accuracy_m"))
        vertical = number(quality.get("vertical_accuracy_m"))
        speed = number(quality.get("native_speed_mps"))
        if speed is None:
            speed = number(payload.get("speed_mps"))
        source = "iphone"
    else:
        return None

    if horizontal is None:
        horizontal = -1
    if vertical is None:
        vertical = -1
    altitude = number(payload.get("altitude_m")) or 0.0
    return Point(ts, lat, lon, altitude, horizontal, vertical, speed, source)


def haversine_m(a: Point, b: Point) -> float:
    radius = 6_371_000.0
    lat1 = math.radians(a.latitude)
    lat2 = math.radians(b.latitude)
    dlat = lat2 - lat1
    dlon = math.radians(b.longitude - a.longitude)
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * radius * math.asin(min(1.0, math.sqrt(h)))


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    index = (len(ordered) - 1) * p
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return ordered[lower]
    weight = index - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def fmt_seconds(value: float | None) -> str:
    return "—" if value is None else f"{value:.2f}s"


def in_pause(ts: float, pauses: list[tuple[float, float]]) -> bool:
    return any(start <= ts <= end for start, end in pauses)


def reconstruct_pauses(rows: Iterable[dict[str, Any]], start: float, end: float) -> list[tuple[float, float]]:
    marks: list[tuple[float, bool]] = []
    for row in rows:
        if row.get("record") != "event" or row.get("source") != "watch":
            continue
        event = row.get("event") or ""
        ts = number(row.get("timestamp"))
        if ts is None or ts < start or ts > end:
            continue
        if event in {"manual_pause", "auto_pause"}:
            marks.append((ts, True))
        elif event in {"manual_resume", "auto_resume"}:
            marks.append((ts, False))
    marks.sort()
    pauses: list[tuple[float, float]] = []
    open_pause: float | None = None
    for ts, is_pause in marks:
        if is_pause:
            if open_pause is None:
                open_pause = ts
        elif open_pause is not None and ts > open_pause:
            pauses.append((open_pause, ts))
            open_pause = None
    if open_pause is not None and end > open_pause:
        pauses.append((open_pause, end))
    return pauses


def analyze_stream(name: str, points: list[Point], start: float, end: float, pauses: list[tuple[float, float]], summary_distance: float) -> dict[str, Any]:
    raw_order_non_monotonic = sum(
        1 for a, b in zip(points, points[1:]) if b.timestamp < a.timestamp
    )
    filtered = [p for p in points if start <= p.timestamp <= end and 0 <= p.horizontal_accuracy <= 50]
    filtered.sort(key=lambda p: p.timestamp)
    deduped: list[Point] = []
    for point in filtered:
        if deduped and abs(point.timestamp - deduped[-1].timestamp) < 1e-6 \
                and abs(point.latitude - deduped[-1].latitude) < 1e-8 \
                and abs(point.longitude - deduped[-1].longitude) < 1e-8:
            continue
        deduped.append(point)

    gaps = [b.timestamp - a.timestamp for a, b in zip(deduped, deduped[1:]) if b.timestamp >= a.timestamp]
    accuracies = [p.horizontal_accuracy for p in deduped]
    path_distance = sum(haversine_m(a, b) for a, b in zip(deduped, deduped[1:]))
    geometry_speeds = [
        haversine_m(a, b) / (b.timestamp - a.timestamp)
        for a, b in zip(deduped, deduped[1:])
        if b.timestamp - a.timestamp > 0
    ]
    paused_points = sum(1 for p in deduped if in_pause(p.timestamp, pauses))
    active_points = len(deduped) - paused_points

    result = {
        "name": name,
        "count": len(deduped),
        "raw_order_non_monotonic": raw_order_non_monotonic,
        "first_offset": deduped[0].timestamp - start if deduped else None,
        "last_offset": end - deduped[-1].timestamp if deduped else None,
        "gap_median": statistics.median(gaps) if gaps else None,
        "gap_p90": percentile(gaps, 0.90),
        "gap_p95": percentile(gaps, 0.95),
        "gap_max": max(gaps) if gaps else None,
        "gaps_gt3": sum(1 for gap in gaps if gap > 3.0),
        "gaps_gt5": sum(1 for gap in gaps if gap > 5.0),
        "gaps_gt10": sum(1 for gap in gaps if gap > 10.0),
        "gaps_gt30": sum(1 for gap in gaps if gap > 30.0),
        "accuracy_median": statistics.median(accuracies) if accuracies else None,
        "accuracy_p90": percentile(accuracies, 0.90),
        "accuracy_max": max(accuracies) if accuracies else None,
        "path_distance": path_distance,
        "distance_delta": path_distance - summary_distance,
        "geometry_speed_max": max(geometry_speeds) if geometry_speeds else None,
        "paused_points": paused_points,
        "active_points": active_points,
    }
    return result


def print_stream(result: dict[str, Any]) -> None:
    print(f"\n=== GPS {result['name'].upper()} ===")
    print(f"points valides           : {result['count']}")
    print(f"ordre non monotone raw   : {result['raw_order_non_monotonic']}")
    print(f"couverture début/fin     : +{fmt_seconds(result['first_offset'])} / -{fmt_seconds(result['last_offset'])}")
    print(
        "gaps méd/p90/p95/max    : "
        f"{fmt_seconds(result['gap_median'])} / {fmt_seconds(result['gap_p90'])} / "
        f"{fmt_seconds(result['gap_p95'])} / {fmt_seconds(result['gap_max'])}"
    )
    print(
        "gaps >3/>5/>10/>30s    : "
        f"{result['gaps_gt3']} / {result['gaps_gt5']} / {result['gaps_gt10']} / {result['gaps_gt30']}"
    )
    print(
        "précision méd/p90/max  : "
        f"{result['accuracy_median']:.1f} / {result['accuracy_p90']:.1f} / {result['accuracy_max']:.1f} m"
        if result['accuracy_median'] is not None else "précision               : —"
    )
    print(f"distance géométrique     : {result['path_distance']:.1f} m")
    print(f"écart vs summary         : {result['distance_delta']:+.1f} m")
    print(
        "vitesse géom max       : "
        + (f"{result['geometry_speed_max'] * 3.6:.1f} km/h" if result['geometry_speed_max'] is not None else "—")
    )
    print(f"points pendant pauses    : {result['paused_points']}")
    print(f"points hors pauses       : {result['active_points']}")


def choose_candidate(watch: dict[str, Any], iphone: dict[str, Any]) -> str:
    def score(item: dict[str, Any]) -> tuple[float, float, float, float]:
        # Lower is better. Fitness rendering is sensitive to temporal continuity,
        # so long gaps dominate point count. Accuracy and distance coherence follow.
        max_gap = item["gap_max"] if item["gap_max"] is not None else 1e9
        p95_gap = item["gap_p95"] if item["gap_p95"] is not None else 1e9
        p90_accuracy = item["accuracy_p90"] if item["accuracy_p90"] is not None else 1e9
        distance_error = abs(item["distance_delta"])
        return (item["gaps_gt10"] * 1000 + item["gaps_gt3"] * 10 + max_gap, p95_gap, p90_accuracy, distance_error)

    ws = score(watch)
    ps = score(iphone)
    if ws < ps:
        return "WATCH"
    if ps < ws:
        return "IPHONE"
    return "ÉGALITÉ"


def main() -> int:
    parser = argparse.ArgumentParser(description="Audit read-only Watch/iPhone GPS for historical HealthKit restore")
    parser.add_argument("--root", required=True, help="Racine du snapshot incident gelé")
    parser.add_argument("--session", required=True, help="Session ID Tracker")
    args = parser.parse_args()

    root = Path(args.root)
    session_dir = find_session_dir(root, args.session)
    summary = json.loads((session_dir / "summary.json").read_text(encoding="utf-8"))
    start = parse_date(summary["startedAt"])
    end = parse_date(summary["endedAt"])
    summary_distance = float(summary.get("distanceMeters") or 0.0)
    active_duration = float(summary.get("duration") or 0.0)

    rows = list(load_jsonl(session_dir / "samples.jsonl"))
    reliable_path = session_dir / "watch_reliable.jsonl"
    if reliable_path.is_file():
        rows.extend(load_jsonl(reliable_path))

    watch_points: list[Point] = []
    iphone_points: list[Point] = []
    for row in rows:
        point = point_from_row(row)
        if point is None:
            continue
        if point.source == "watch":
            watch_points.append(point)
        elif point.source == "iphone":
            iphone_points.append(point)

    pauses = reconstruct_pauses(rows, start, end)
    pause_duration = sum(max(0.0, b - a) for a, b in pauses)

    print("TRACKER HISTORICAL ROUTE AUDIT — READ ONLY")
    print(f"session                 : {args.session}")
    print(f"source dir              : {session_dir}")
    print(f"début UTC               : {datetime.fromtimestamp(start, timezone.utc).isoformat()}")
    print(f"fin UTC                 : {datetime.fromtimestamp(end, timezone.utc).isoformat()}")
    print(f"durée murale            : {end - start:.3f} s")
    print(f"durée active summary    : {active_duration:.3f} s")
    print(f"distance summary        : {summary_distance:.3f} m")
    print(f"pauses reconstruites    : {len(pauses)} / {pause_duration:.3f} s")

    watch = analyze_stream("watch", watch_points, start, end, pauses, summary_distance)
    iphone = analyze_stream("iphone", iphone_points, start, end, pauses, summary_distance)
    print_stream(watch)
    print_stream(iphone)

    print("\n=== DIAGNOSTIC ROUTE ===")
    print(f"candidat temporel       : {choose_candidate(watch, iphone)}")
    for item in (watch, iphone):
        warnings: list[str] = []
        if item["gaps_gt3"] > 0:
            warnings.append(f"{item['gaps_gt3']} gaps >3s")
        if item["gaps_gt10"] > 0:
            warnings.append(f"{item['gaps_gt10']} gaps >10s")
        if item["first_offset"] is not None and item["first_offset"] > 10:
            warnings.append("début de route tardif")
        if item["last_offset"] is not None and item["last_offset"] > 10:
            warnings.append("fin de route précoce")
        if item["raw_order_non_monotonic"] > 0:
            warnings.append("timestamps non monotones dans le raw")
        if item["geometry_speed_max"] is not None and item["geometry_speed_max"] > 30:
            warnings.append("saut GPS géométrique >108 km/h")
        print(f"{item['name']:<6}                 : " + (", ".join(warnings) if warnings else "aucun drapeau majeur"))

    print("\nAUCUNE DONNÉE N'A ÉTÉ MODIFIÉE.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
