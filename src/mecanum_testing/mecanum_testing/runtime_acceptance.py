#!/usr/bin/env python3
"""Headless end-to-end motion and Nav2 acceptance for the simulation profile."""

import argparse
import math
import threading
import time

import rclpy
from action_msgs.msg import GoalStatus
from geometry_msgs.msg import TwistStamped
from nav2_msgs.action import NavigateToPose
from nav_msgs.msg import Odometry
from rclpy.action import ActionClient
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node


def yaw_of(q):
    return math.atan2(2.0 * (q.w * q.z + q.x * q.y),
                      1.0 - 2.0 * (q.y * q.y + q.z * q.z))


def angle_delta(a, b):
    return math.atan2(math.sin(a - b), math.cos(a - b))


class Acceptance(Node):
    def __init__(self):
        super().__init__('runtime_acceptance')
        self._lock = threading.Lock()
        self._odom = None
        self._pub = self.create_publisher(TwistStamped, '/cmd_vel_teleop', 10)
        self.create_subscription(Odometry, '/ground_truth/odom', self._on_odom, 10)
        self._nav = ActionClient(self, NavigateToPose, '/navigate_to_pose')

    def _on_odom(self, msg):
        with self._lock:
            self._odom = msg

    def pose(self):
        with self._lock:
            msg = self._odom
        if msg is None:
            return None
        return (msg.pose.pose.position.x, msg.pose.pose.position.y,
                yaw_of(msg.pose.pose.orientation))

    def wait_odom(self, timeout=30.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.pose() is not None:
                return True
            time.sleep(0.1)
        return False

    def command(self, vx=0.0, vy=0.0, wz=0.0, seconds=1.4):
        msg = TwistStamped()
        msg.header.frame_id = 'base_footprint'
        msg.twist.linear.x = vx
        msg.twist.linear.y = vy
        msg.twist.angular.z = wz
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            msg.header.stamp = self.get_clock().now().to_msg()
            self._pub.publish(msg)
            time.sleep(0.02)
        msg.twist.linear.x = msg.twist.linear.y = msg.twist.angular.z = 0.0
        for _ in range(25):
            msg.header.stamp = self.get_clock().now().to_msg()
            self._pub.publish(msg)
            time.sleep(0.02)

    def motion_case(self, name, vx=0.0, vy=0.0, wz=0.0):
        before = self.pose()
        self.command(vx, vy, wz)
        time.sleep(0.5)
        after = self.pose()
        if before is None or after is None:
            print(f'FAIL  hareket {name}: ground truth yok')
            return False
        dxw, dyw = after[0] - before[0], after[1] - before[1]
        c, s = math.cos(before[2]), math.sin(before[2])
        dx, dy = c * dxw + s * dyw, -s * dxw + c * dyw
        dyaw = angle_delta(after[2], before[2])
        expected = vx if vx else (vy if vy else wz)
        observed = dx if vx else (dy if vy else dyaw)
        threshold = 0.035 if (vx or vy) else 0.06
        ok = observed * expected > 0.0 and abs(observed) >= threshold
        print(f'{"PASS" if ok else "FAIL"}  hareket {name}: '
              f'dx={dx:+.3f} dy={dy:+.3f} dyaw={dyaw:+.3f}')
        return ok

    def nav_goal(self, x, y, timeout):
        if not self._nav.wait_for_server(timeout_sec=30.0):
            print('FAIL  Nav2 hedefi: action server yok')
            return False
        goal = NavigateToPose.Goal()
        goal.pose.header.frame_id = 'map'
        goal.pose.header.stamp = self.get_clock().now().to_msg()
        goal.pose.pose.position.x = x
        goal.pose.pose.position.y = y
        goal.pose.pose.orientation.w = 1.0
        send = self._nav.send_goal_async(goal)
        if not wait_future(send, 15.0) or not send.result().accepted:
            print('FAIL  Nav2 hedefi: hedef kabul edilmedi')
            return False
        result = send.result().get_result_async()
        if not wait_future(result, timeout):
            send.result().cancel_goal_async()
            print(f'FAIL  Nav2 hedefi: {timeout:.0f} s zaman aşımı')
            return False
        status = result.result().status
        ok = status == GoalStatus.STATUS_SUCCEEDED
        print(f'{"PASS" if ok else "FAIL"}  Nav2 hedefi ({x:+.2f}, {y:+.2f}): '
              f'status={status} (SUCCEEDED={GoalStatus.STATUS_SUCCEEDED})')
        return ok


def wait_future(future, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if future.done():
            return True
        time.sleep(0.05)
    return False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--goal-x', type=float, default=-0.8)
    parser.add_argument('--goal-y', type=float, default=1.5)
    parser.add_argument('--nav-timeout', type=float, default=120.0)
    args = parser.parse_args()

    rclpy.init()
    node = Acceptance()
    executor = MultiThreadedExecutor()
    executor.add_node(node)
    thread = threading.Thread(target=executor.spin, daemon=True)
    thread.start()
    ok = node.wait_odom()
    if not ok:
        print('FAIL  /ground_truth/odom alınamadı')
    else:
        for name, vx, vy, wz in [
            ('ileri', 0.12, 0.0, 0.0), ('geri', -0.12, 0.0, 0.0),
            ('sola', 0.0, 0.12, 0.0), ('sağa', 0.0, -0.12, 0.0),
            ('saat_yonu_tersi', 0.0, 0.0, 0.20),
            ('saat_yonu', 0.0, 0.0, -0.20),
        ]:
            ok = node.motion_case(name, vx, vy, wz) and ok
        ok = node.nav_goal(args.goal_x, args.goal_y, args.nav_timeout) and ok
    node.command(seconds=0.2)
    executor.shutdown()
    node.destroy_node()
    rclpy.shutdown()
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
