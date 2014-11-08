/// The hound_blog library.
///
/// Library to help produce statically generated blog sites.
///
/// More dartdocs go here.
library hound_blog;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:barback/barback.dart';
import 'package:mustache4dart/mustache4dart.dart' as mustache;
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Combines html files starting with _ as pages.
/// Files matching .div.html or .article.html are treated as fragments of pages.
/// Consumes the _ files and emits (name).html pages.
class HoundBlog extends AggregateTransformer {
  /// Constucts plugin. Relies on two assumptions:
  /// 1. Called with the current directory being the root of the actual project
  /// 2. Called just once (should be fine, but does unnecessary work)
  HoundBlog.asPlugin(this._settings) {
    var yamlFile = new File("${Directory.current.path}${Platform.pathSeparator}pubspec.yaml");
    if (yamlFile.existsSync()) {
      var yamlData = yamlFile.readAsStringSync();
      extractPubspecYaml(yamlData, _mustacheHash);
    }

    var args = _settings.configuration;
    var explicitTargetFiles = args["explicit_target_files"];
    if (explicitTargetFiles != null) {
      if (explicitTargetFiles is List) {
        _explictTargetFiles.addAll(explicitTargetFiles);
      } else if (explicitTargetFiles is String) {
        _explictTargetFiles.add(explicitTargetFiles);
      }

      if (_explictTargetFiles != null) {
        print("[Info from hound_blog] explicit_target_files = ${_explictTargetFiles.join(",")}");
      }
    }

    var outputMustacheHash = args["output_mustache_hash"];
    if (outputMustacheHash != null && outputMustacheHash is bool) {
      _outputMustacheHash = outputMustacheHash;
    }
  }

  /// Runs this transformer on a group of primary inputs specified by
  /// [transform].
  ///
  /// If this does asynchronous work, it should return a [Future] that completes
  /// once it's finished.
  ///
  /// This may complete before [AggregateTransform.primarInputs] is closed. For
  /// example, it may know that each key will only have two inputs associated
  /// with it, and so use `transform.primaryInputs.take(2)` to access only those
  /// inputs.
  ///
  /// See: https://www.dartlang.org/tools/pub/transformers/aggregate.html
  Future apply(AggregateTransform transform) {
    List<Asset> articleFragments = new List<Asset>();
    List<Asset> divFragments = new List<Asset>();
    List<Asset> pages = new List<Asset>();

    return transform.primaryInputs.toList().then((List<Asset> assets) {
      for (var asset in assets) {
        var assetName = path.url.basename(asset.id.path);

        if (assetName.endsWith("div.html")) {
          divFragments.add(asset);
        } else if (assetName.endsWith("article.html")) {
          articleFragments.add(asset);
        } else {
          pages.add(asset);
        }

        // We claim all these assets in the name of hound.
        // Do not output these, do not let other processors process them.
        if (asset.id.path.endsWith("html")) {
          transform.consumePrimary(asset.id);
        }
      }

      // Declaring sink here assumes single threaded no contention.
      var sink = new StringBuffer();
      var idSink = new StringBuffer();

      //TODO: Render div fragments first, store them in hash context using naming convention.
      //TODO: Then render article fragments  store them in hash context using naming convention.
      return Future.wait(divFragments.map((asset) {
        return asset.readAsString().then((template) {
          sink.clear();
          idSink.clear();
          mustache.render(template, _mustacheHash, out: sink);

          var id = _assetId(asset.id.path, idSink);
          _mustacheHash[id] = sink.toString();
        });
      })).then((_) {
        return Future.wait(articleFragments.map((asset) {
          return asset.readAsString().then((template) {
            sink.clear();
            idSink.clear();
            mustache.render(template, _mustacheHash, out: sink);

            var id = _assetId(asset.id.path, idSink);
            _mustacheHash[id] = sink.toString();
          });
        }));
      }).then((_) {
        return Future.wait(pages.map((asset) {
          return asset.readAsString().then((template) {
            sink.clear();
            mustache.render(template, _mustacheHash, out: sink);

            var assetPath = asset.id.path;
            var assetBasename = path.url.basename(assetPath);
            var assetDirPath = path.url.dirname(assetPath);
            var newAssetBasename = (assetBasename.startsWith("_")) ? assetBasename.substring(1) : assetBasename; // chop off the _
            var newAssetPath = "$assetDirPath${Platform.pathSeparator}$newAssetBasename";
            var id = new AssetId(transform.package, newAssetPath);
            transform.addOutput(new Asset.fromString(id, sink.toString()));
          });
        }));
      }).then((_) {
        if (_outputMustacheHash) {
          print("[Info from hound_blog] Mustache Context BEGIN");
          _mustacheHash.forEach((k,v) {
            print("[Info from hound_blog] [$k] = $v");
          });
          print("[Info from hound_blog] Mustache Context END");
        }
      });
    });
  }

  /// Classifies an asset id by returning a key identifying which group the
  /// asset should be placed in.
  ///
  /// All assets for which [classifyPrimary] returns the same key are passed
  /// together to the same [apply] call.
  ///
  /// This may return [Future<String>] or, if it's entirely synchronous,
  /// [String]. Any string can be used to classify an asset. If possible,
  /// though, this should return a path-like string to aid in logging.
  ///
  /// A return value of `null` indicates that the transformer is not interested
  /// in an asset. Assets with a key of `null` will not be passed to any [apply]
  /// call; this is equivalent to [Transformer.isPrimary] returning `false`.
  String classifyPrimary(AssetId id) {
    //var _completer = new Completer<String>();
    var assetPath = id.path;
    var assetName = path.url.basename(assetPath);

    if (assetName.startsWith("_") && assetName.endsWith(".html")) {
      return "hounds";
    } else if (_explictTargetFiles.contains(assetPath)) {
      return "hounds";
    }

    return null;
  }

  /// Creates asset id from path
  String _assetId(String assetPath, StringBuffer idSink) {
    idSink.clear();

    var assetBasename = path.url.basename(assetPath);
    var assetDirPath = path.url.dirname(assetPath);
    var assetDirComponents = path.url.split(assetPath);
    int assetDirComponentsLength = assetDirComponents.length;
    for (int i = 0; i < assetDirComponentsLength; i++) {
      idSink.write("${_regexStripUnderscore.firstMatch(assetDirComponents[i]).group(0)}_");
    }

    idSink.write(assetBasename);
    return idSink.toString();
  }

  /// Files that should be explicitly included that would normally be implicitly ignored.
  final List<String> _explictTargetFiles = new List<String>();

  /// Mustache context hash used to render pages.
  final HashMap _mustacheHash = new HashMap();

  /// Strip underscore
  final RegExp _regexStripUnderscore = new RegExp('''_*(\w+)''');

  /// Settings from pubspec.yaml
  final BarbackSettings _settings;

  /// Output mustache hash
  bool _outputMustacheHash = false;
}

/// Add git metadata to mustache context
void extractGitData(Directory gitDirectory, Map result) {
  result["git_branch"] = "TODO";
  result["git_sha1"] = "TODO";
}

/// Add yaml metadata to mustache context
void extractPubspecYaml(String yaml, Map result) {
  var doc = loadYaml(yaml);
  result["pubspec_name"] = doc["name"];
  result["pubspec_version"] = doc["version"];
  result["pubspec_description"] = doc["description"];
}
