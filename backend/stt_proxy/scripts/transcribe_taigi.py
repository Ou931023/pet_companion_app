#!/usr/bin/env python3
import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description="Transcribe Taiwanese audio")
    parser.add_argument("--audio", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--original-filename", default="")
    parser.add_argument("--mime-type", default="")
    args = parser.parse_args()

    try:
        import torch  # noqa: F401
        from transformers import pipeline
    except Exception as error:
        print(str(error), file=sys.stderr)
        print(
            json.dumps(
                {
                    "error": "TAIGI_ASR_UNAVAILABLE",
                    "message": "Taigi ASR Python dependencies are not installed",
                },
                ensure_ascii=False,
            )
        )
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
        print(
            json.dumps(
                {
                    "language": "taigi",
                    "transcript": transcript,
                    "confidence": 0.0,
                    "source": "taigi-asr",
                },
                ensure_ascii=False,
            )
        )
    except Exception as error:
        print(str(error), file=sys.stderr)
        print(
            json.dumps(
                {
                    "error": "TAIGI_ASR_PROVIDER_ERROR",
                    "message": "Taigi ASR inference failed",
                },
                ensure_ascii=False,
            )
        )


if __name__ == "__main__":
    main()
