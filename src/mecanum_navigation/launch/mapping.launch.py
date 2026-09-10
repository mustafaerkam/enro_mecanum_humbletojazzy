"""
Yalniz slam_toolbox mapping oturumu (mode: mapping). map_server ve AMCL
ICERMEZ. localization.launch.py ile AYNI ust agacta calismamalidir — ikisi
de map->odom yayinlar, tek-sahip kuralini bozar (bu launch bunu kendi
basina engelleyemez; mecanum_bringup sim_nav.launch.py / sim_mapping.launch.py
ayrimi bu ikisinin asla birlikte include edilmemesini garanti eder).

Onkosul: simulation.launch.py + mecanum_control/controllers.launch.py calisir
durumda (scan, wheel/odometry, imu/data_raw yayinda) VE mecanum_navigation/
ekf.launch.py aktif olmalidir (slam_toolbox odom_frame'i EKF'nin ciktisini
kullanir).

Kullanim:
  ros2 launch mecanum_navigation mapping.launch.py use_sim_time:=true
Harita kaydetme (harita tamamlaninca):
  ros2 run nav2_map_server map_saver_cli -f /home/<kullanici>/harita_adi
"""
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (DeclareLaunchArgument, EmitEvent, LogInfo,
                            RegisterEventHandler)
from launch.conditions import IfCondition
from launch.events import matches_action
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import LifecycleNode
from launch_ros.event_handlers import OnStateTransition
from launch_ros.events.lifecycle import ChangeState
from lifecycle_msgs.msg import Transition


def generate_launch_description():
    pkg_share = get_package_share_directory('mecanum_navigation')
    slam_params = os.path.join(pkg_share, 'config', 'slam_toolbox.yaml')

    use_sim_time = LaunchConfiguration('use_sim_time')

    autostart = LaunchConfiguration('autostart')

    # JAZZY: async_slam_toolbox_node bir LIFECYCLE dugumudur. Duz Node olarak
    # baslatilirsa 'unconfigured' durumunda kalir; /map yayinlanmaz ve
    # map->odom TF'i hic olusmaz (olculdu: lifecycle get -> unconfigured,
    # /map yok, tf2_echo map->odom "frame does not exist"). Bu yuzden
    # configure/activate gecisleri acikca tetiklenir.
    #
    # use_lifecycle_manager=false: bu agacta slam_toolbox'i yoneten bir Nav2
    # lifecycle_manager YOKTUR (mapping oturumunda Nav2 calismaz). Gecisleri
    # asagidaki event'ler yapar. Desen resmi ornekten alinmistir:
    #   /opt/ros/jazzy/share/slam_toolbox/launch/online_async_launch.py
    slam_node = LifecycleNode(
        package='slam_toolbox',
        executable='async_slam_toolbox_node',
        name='slam_toolbox',
        namespace='',
        output='screen',
        parameters=[
            slam_params,
            {
                'use_sim_time': use_sim_time,
                'use_lifecycle_manager': False,
            },
        ],
    )

    configure_event = EmitEvent(
        event=ChangeState(
            lifecycle_node_matcher=matches_action(slam_node),
            transition_id=Transition.TRANSITION_CONFIGURE,
        ),
        condition=IfCondition(autostart),
    )

    activate_event = RegisterEventHandler(
        OnStateTransition(
            target_lifecycle_node=slam_node,
            start_state='configuring',
            goal_state='inactive',
            entities=[
                LogInfo(msg='[mapping] slam_toolbox activate ediliyor.'),
                EmitEvent(event=ChangeState(
                    lifecycle_node_matcher=matches_action(slam_node),
                    transition_id=Transition.TRANSITION_ACTIVATE,
                )),
            ],
        ),
        condition=IfCondition(autostart),
    )

    return LaunchDescription([
        DeclareLaunchArgument('use_sim_time', default_value='true'),
        DeclareLaunchArgument(
            'autostart', default_value='true',
            description='slam_toolbox lifecycle gecislerini otomatik yap.'),
        slam_node,
        configure_event,
        activate_event,
    ])
