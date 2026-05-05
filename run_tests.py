import json
import urllib.request
import re
import time

def run_tests():
    print("Reading tool_test_plan.md...")
    with open("Project_Wiki/tool_test_plan.md", "r", encoding="utf-8") as f:
        content = f.read()

    tests = []
    # Match markdown tables. Example row:
    # | T-01 | `get_system_info` | `sistemin donanım bilgilerini göster` | macOS sürümü...
    for line in content.splitlines():
        if line.startswith("|") and not "---" in line and not "Beklenen" in line:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 4:
                test_id = parts[1].replace("`", "").strip()
                if not test_id or test_id == "#" or test_id == "Araç": continue
                
                # Handling sections where tool is omitted like Intent Classification
                if test_id.startswith("I-") or test_id.startswith("N-") or test_id.startswith("P-") or test_id.startswith("S-"):
                    prompt = parts[2].replace("`", "").strip()
                else:
                    prompt = parts[3].replace("`", "").strip()
                
                if not prompt or prompt.startswith("*("): continue
                if test_id.startswith("T-") or test_id.startswith("I-") or test_id.startswith("N-") or test_id.startswith("S-"):
                    tests.append((test_id.split()[0], prompt))

    print(f"Found {len(tests)} tests. Executing...")
    
    results = []
    for tid, prompt in tests:
        print(f"Running [{tid}] Prompt: {prompt}")
        data = json.dumps({"prompt": prompt, "workspace": None}).encode('utf-8')
        req = urllib.request.Request("http://localhost:11500/api/agent", data=data, headers={'Content-Type': 'application/json'})
        
        start = time.time()
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                res_data = json.loads(response.read().decode('utf-8'))
                elapsed = time.time() - start
                print(f"  -> Success ({elapsed:.1f}s): {res_data.get('response', '')[:50]}...")
                results.append((tid, "SUCCESS", res_data.get('response', ''), res_data.get('toolsUsed', [])))
        except Exception as e:
            elapsed = time.time() - start
            print(f"  -> Failed ({elapsed:.1f}s): {str(e)}")
            results.append((tid, "FAILED", str(e), []))
            
    with open("test_results.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    run_tests()
