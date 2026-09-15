"""Train 极速者 V3 generic-threat + combat policy with PPO.

Editor training:
    1) Activate the Python 3.11 venv.
    2) Run this script first.
    3) Run res://scenes/training/SpeedsterRLWorld.tscn in Godot.

Important:
    - No --resume / --auto-resume: start a fresh PPO model.
    - --resume PATH: continue from that .zip model.
    - --auto-resume: continue from the default final model if it exists; otherwise start fresh.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from godot_rl.wrappers.onnx.stable_baselines_export import export_model_as_onnx
from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback
from stable_baselines3.common.vec_env import VecMonitor


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-path", default=None)
    parser.add_argument("--timesteps", type=int, default=1_000_000)
    parser.add_argument("--speedup", type=int, default=1)
    parser.add_argument("--n-parallel", type=int, default=1)
    parser.add_argument("--action-repeat", type=int, default=1)
    parser.add_argument("--save-dir", default="rl_training/runs/SpeedsterThreatCombat_v3")
    parser.add_argument("--resume", default=None, help="Path to an SB3 .zip model to continue training from")
    parser.add_argument(
        "--auto-resume",
        action="store_true",
        help="Resume from <save-dir>/speedster_v3_final.zip if it exists; otherwise start fresh",
    )
    parser.add_argument("--viz", action="store_true")
    parser.add_argument("--onnx", default="rl_training/models/SpeedsterThreatCombat_v3.onnx")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    save_dir = Path(args.save_dir)
    save_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = Path(args.onnx).with_suffix(".onnx")
    onnx_path.parent.mkdir(parents=True, exist_ok=True)

    final_model = save_dir / "speedster_v3_final.zip"
    resume_path: Path | None = Path(args.resume) if args.resume else None
    if args.auto_resume and resume_path is None and final_model.exists():
        resume_path = final_model

    env = StableBaselinesGodotEnv(
        env_path=args.env_path,
        show_window=args.viz,
        n_parallel=args.n_parallel,
        speedup=args.speedup,
        action_repeat=args.action_repeat,
    )
    env = VecMonitor(env)

    if resume_path is not None:
        if not resume_path.exists():
            raise FileNotFoundError(f"Resume model not found: {resume_path}")
        print(f"[Speedster V3] Resuming model: {resume_path.resolve()}")
        model = PPO.load(resume_path, env=env, tensorboard_log=str(save_dir / "tb"))
        reset_num_timesteps = False
    else:
        print("[Speedster V3] Starting a fresh PPO model.")
        model = PPO(
            "MultiInputPolicy",
            env,
            learning_rate=3e-4,
            n_steps=256,
            batch_size=256,
            gamma=0.985,
            gae_lambda=0.95,
            ent_coef=0.01,
            clip_range=0.2,
            verbose=2,
            tensorboard_log=str(save_dir / "tb"),
        )
        reset_num_timesteps = True

    checkpoint_dir = save_dir / "checkpoints"
    checkpoint_dir.mkdir(parents=True, exist_ok=True)
    checkpoint = CheckpointCallback(
        save_freq=max(50_000 // max(args.n_parallel, 1), 1),
        save_path=str(checkpoint_dir),
        name_prefix="speedster_v3",
    )

    try:
        model.learn(
            total_timesteps=args.timesteps,
            callback=checkpoint,
            tb_log_name="ppo",
            reset_num_timesteps=reset_num_timesteps,
        )
    finally:
        # SB3 会自动补 .zip；这里传无后缀路径避免 .zip.zip。
        final_model_no_suffix = save_dir / "speedster_v3_final"
        model.save(str(final_model_no_suffix))
        export_model_as_onnx(model, str(onnx_path))
        print(f"[Speedster V3] Saved SB3 model: {final_model_no_suffix}.zip")
        print(f"[Speedster V3] Exported ONNX: {onnx_path}")
        env.close()


if __name__ == "__main__":
    main()
