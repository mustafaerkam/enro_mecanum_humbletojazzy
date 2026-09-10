"""RPLIDAR A1M8 driver with this robot's stable device and TF contract."""

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument('serial_port', default_value='/dev/mecanum_lidar'),
        DeclareLaunchArgument('serial_baudrate', default_value='115200'),
        DeclareLaunchArgument('frame_id', default_value='lidar_link'),
        DeclareLaunchArgument('scan_mode', default_value='Sensitivity'),
        Node(
            package='rplidar_ros',
            executable='rplidar_node',
            name='rplidar_node',
            output='screen',
            parameters=[{
                'serial_port': LaunchConfiguration('serial_port'),
                'serial_baudrate': LaunchConfiguration('serial_baudrate'),
                'frame_id': LaunchConfiguration('frame_id'),
                'inverted': False,
                'angle_compensate': True,
                'scan_mode': LaunchConfiguration('scan_mode'),
            }],
        ),
    ])
