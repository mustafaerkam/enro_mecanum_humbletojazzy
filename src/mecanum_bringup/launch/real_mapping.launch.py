"""Real robot control + EKF + SLAM with the shared safe command chain.

The micro-ROS agent and the RPLIDAR A1M8 driver are intentionally
separate processes. Verify both sensor topics before enabling motors.
"""
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, LogInfo
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    bringup_share = get_package_share_directory('mecanum_bringup')
    desc_share = get_package_share_directory('mecanum_robot_description')
    control_share = get_package_share_directory('mecanum_control')
    nav_share = get_package_share_directory('mecanum_navigation')

    transport = LaunchConfiguration('transport')
    command_topic = LaunchConfiguration('command_topic')
    state_topic = LaunchConfiguration('state_topic')
    feedback_mode = LaunchConfiguration('feedback_mode')
    controller_config = os.path.join(control_share, 'config', 'mecanum_controllers.yaml')

    description = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(desc_share, 'launch', 'description.launch.py')),
        launch_arguments={
            'robot_variant': 'real',
            'use_sim_time': 'false',
            'transport': transport,
            'command_topic': command_topic,
            'state_topic': state_topic,
            'feedback_mode': feedback_mode,
        }.items(),
    )
    controller_manager = Node(
        package='controller_manager', executable='ros2_control_node', output='screen',
        parameters=[controller_config, {'use_sim_time': False}],
        remappings=[
            ('robot_description', '/robot_description'),
            ('mecanum_drive_controller/odometry', 'wheel/odometry'),
            ('mecanum_drive_controller/reference', 'cmd_vel'),
        ],
    )
    controllers = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(control_share, 'launch', 'controllers.launch.py')),
        launch_arguments={
            'use_sim_time': 'false',
            'controller_config': controller_config,
        }.items(),
    )
    ekf = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(nav_share, 'launch', 'ekf.launch.py')),
        launch_arguments={'use_sim_time': 'false'}.items(),
    )
    mapping = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(os.path.join(nav_share, 'launch', 'mapping.launch.py')),
        launch_arguments={'use_sim_time': 'false'}.items(),
    )
    safety_chain = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(nav_share, 'launch', 'safety_chain.launch.py')),
        launch_arguments={
            'use_sim_time': 'false',
            'stop_polygon_enabled': 'true',
        }.items(),
    )
    twist_mux = Node(
        package='twist_mux', executable='twist_mux', name='twist_mux', output='screen',
        parameters=[
            os.path.join(bringup_share, 'config', 'twist_mux.yaml'),
            {'use_sim_time': False},
        ],
        remappings=[('cmd_vel_out', 'cmd_vel_selected')],
    )
    return LaunchDescription([
        DeclareLaunchArgument('transport', default_value='mock'),
        DeclareLaunchArgument('command_topic', default_value='wheel/commands'),
        DeclareLaunchArgument('state_topic', default_value='wheel/states'),
        DeclareLaunchArgument('feedback_mode', default_value='required'),
        LogInfo(msg=[
            'micro_ros_agent ve RPLIDAR A1M8 surucusu ayri baslatilmalidir. ',
            'Motorlari etkinlestirmeden once /scan, /imu/data_raw ve wheel/states kontrol edin.',
        ]),
        description,
        controller_manager,
        controllers,
        twist_mux,
        ekf,
        mapping,
        safety_chain,
    ])
