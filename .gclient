solutions = [
  {
    "url": "https://chromium.googlesource.com/chromium/src.git",
    "managed": False,
    "name": "src",
    "custom_deps": {
        "src/third_party/depot_tools": None,
        "src/third_party/espresso": None,
        "src/third_party/netty-tcnative/src": None,
        "src/third_party/netty4/src": None,
        "src/tools/luci-go": None,
        "src/chrome/test/data/xr/webvr_info": None,
        "src/third_party/quic_trace/src": None,
        "src/third_party/webgl/src": None,
        "src/third_party/hunspell_dictionaries": None,
        "src/third_party/apache-portable-runtime/src": None,
        "src/third_party/requests/src": None,
        "src/third_party/libFuzzer/src": None,
        "src/third_party/libprotobuf-mutator/src": None,
        "src/third_party/webdriver/pylib": None,
        "src/chrome/test/data/perf/canvas_bench": None,
        "src/chrome/test/data/perf/frame_rate/content": None,
    },
    "custom_vars": {
        "checkout_configuration": "small",
        "checkout_telemetry_dependencies": False,
    },
  },
]
hooks = [
  {
    'name': 'fetch_filter_lists',
    'condition': 'checkout_android',
    'action': ['python3',
              '../vanadium/tools/filter_lists/filter_list_download.py',
              '--output',
              'src/vanadium/android_config/filter_lists/filter_lists_easylist.txt',
              '--urls',
              'https://easylist-downloads.adblockplus.org/antiadblockfilters.txt',
              'https://easylist.to/easylist/easylist.txt',
              'https://easylist.to/easylist/easyprivacy.txt',
              'https://easylist-downloads.adblockplus.org/easylistchina.txt']
  },
  {
    'name': 'apply_subprojects_patches',
    'condition': 'checkout_android',
    'action': ['python3',
              '../vanadium/tools/common/apply_subprojects_patches.py',
              '--base_patch_dir',
              '../vanadium/subprojects_patches',
              '--src_dir',
              'src']
  },
]
target_os = ['android']
