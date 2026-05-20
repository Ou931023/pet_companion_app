#!/usr/bin/env python3
import argparse
import json
import sys


def print_json(payload):
    print(json.dumps(payload, ensure_ascii=False))


def import_dependencies():
    import torch  # noqa: F401
    import soundfile  # noqa: F401
    from transformers import AutoConfig, pipeline

    return AutoConfig, pipeline


def main():
    parser = argparse.ArgumentParser(description="Transcribe Taiwanese audio")
    parser.add_argument("--audio")
    parser.add_argument("--model", required=True)
    parser.add_argument("--original-filename", default="")
    parser.add_argument("--mime-type", default="")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    try:
        AutoConfig, pipeline = import_dependencies()
    except Exception as error:
        print(str(error), file=sys.stderr)
        print_json({
            "error": "TAIGI_ASR_UNAVAILABLE",
            "message": "Taigi ASR Python dependencies are not installed",
        })
        return 0

    if args.dry_run:
        try:
            AutoConfig.from_pretrained(args.model)
            print_json({
                "ok": True,
                "mode": "dry-run",
            })
        except Exception as error:
            print(str(error), file=sys.stderr)
            print_json({
                "ok": False,
                "error": "TAIGI_ASR_UNAVAILABLE",
                "message": "Taigi ASR model is not available",
            })
        return 0

    if not args.audio:
        print_json({
            "error": "TAIGI_ASR_AUDIO_MISSING",
            "message": "Audio path is required",
        })
        return 0

    try:
        asr = pipeline(
            "automatic-speech-recognition",
            model=args.model,
        )
        result = asr(args.audio)
        transcript = ""
        if isinstance(result, dict):
            transcript = str(result.get("text") or "").strip()
        else:
            transcript = str(result or "").strip()
        print_json({
            "language": "taigi",
            "transcript": transcript,
            "confidence": 0.0,
            "source": "taigi-asr",
        })
    except Exception as error:
        print(str(error), file=sys.stderr)
        print_json({
            "error": "TAIGI_ASR_PROVIDER_ERROR",
            "message": "Taigi ASR inference failed",
        })


if __name__ == "__main__":
    main()
