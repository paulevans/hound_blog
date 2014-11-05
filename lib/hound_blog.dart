/// The hound_blog library.
///
/// This is an awesome library. More dartdocs go here.
library hound_blog;

import 'dart:async';
import 'dart:io';
import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;

class HoundBlog extends AggregateTransformer
{
  final BarbackSettings _settings;

  HoundBlog.asPlugin(this._settings) {
    var yamlFile = new File("${Directory.current.path}${Platform.pathSeparator}pubspec.yaml");
    if (yamlFile.existsSync()) {
      print("booya");
    }
    else
    {
      print(":( :( :(");
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
  Future apply(AggregateTransform transform) {
    //TODO: https://www.dartlang.org/tools/pub/transformers/aggregate.html

    List<Asset> articleFragments = new List<Asset>();
    List<Asset> divFragments = new List<Asset>();

    return transform.primaryInputs.toList()
        .then((List<Asset> assets) {
      for (var asset in assets) {
        print("[${transform.key}] = ${asset.id.path} ... ${path.url.dirname(assets[0].id.path)}");
      }

      //TODO: collect and transform div fragments
      //TODO: collect articles
      //TODO: Use divFragments to transform articles
      //TODO: Output only articles, stripping _ from filename
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
  Future<String> classifyPrimary(AssetId id) {
    var _completer = new Completer<String>();
    var assetPath = id.path;
    var assetName = path.url.basename(assetPath);

    if (assetName.startsWith("_") && assetName.endsWith(".html")) {
      // Want to process entire site
      _completer.complete("hounds");
    } else if (assetName.contains("pubspec.yaml")) {
      _completer.complete("yaml");
    }
    else {
      // Do not consume anything that doesn't fit our interest filter
      _completer.complete(null);
    }

    return _completer.future;
  }
}