# Examples

Two ways to see the `/ask` contract in action once `uvicorn ask_service:app` is running.

| File | What it shows |
|---|---|
| `ask_demo.sh` | curl walkthrough: health check, English + Hindi text questions, an off-pack jailbreak attempt (refused, not invented), a quiz, and a package download |
| `ask_client.py` | A minimal Python client — text, recorded audio, or a camera frame in, spoken reply saved to disk |

```bash
cd backend
./examples/ask_demo.sh
# or, against the deployed instance with auth:
BASE_URL=https://<your-app>.azurewebsites.net APP_KEY=<key> ./examples/ask_demo.sh

python examples/ask_client.py --text "Why does the marble glow?"
python examples/ask_client.py --audio my_question.m4a --lang hi
```

Both read `BASE_URL` and `APP_KEY` from the environment so the same script works against `localhost:8000` or a deployed instance.
