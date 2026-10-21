const path = require('path');
const HtmlWebpackPlugin = require('html-webpack-plugin');

module.exports = {
  entry: {
    app: './ui/src/main.tsx',
    admin: './ui/src/admin.tsx',
  },
  output: {
    path: path.resolve(__dirname, 'ui/dist'),
    filename: '[name].js',
    clean: true,
  },
  resolve: {
    extensions: ['.ts', '.tsx', '.js', '.jsx'],
  },
  module: {
    rules: [
      { test: /\.tsx?$/, use: 'ts-loader', exclude: /node_modules/ },
      { test: /\.css$/i, use: ['style-loader', 'css-loader'] },
    ],
  },
  plugins: [
    new HtmlWebpackPlugin({ template: './ui/src/index.html', filename: 'index.html', chunks: ['app'] }),
    new HtmlWebpackPlugin({ template: './ui/src/index.html', filename: 'admin.html', chunks: ['admin'] }),
  ],
  devtool: 'source-map',
};
