import 'package:flutter/material.dart';

class TransferQueueScreen extends StatefulWidget {
  const TransferQueueScreen({super.key});

  @override
  _TransferQueueScreenState createState() => _TransferQueueScreenState();
}

class _TransferQueueScreenState extends State<TransferQueueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('传输队列'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: '进行中'),
            Tab(text: '已完成'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 进行中
          ListView(
            children: [
              // 模拟数据
              ListTile(
                title: Text('file1.txt'),
                subtitle: Text('上传中'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: Icon(Icons.pause), onPressed: () {}),
                    IconButton(icon: Icon(Icons.cancel), onPressed: () {}),
                  ],
                ),
              ),
            ],
          ),
          // 已完成
          ListView(
            children: [
              // 模拟数据
              ListTile(title: Text('file2.txt'), subtitle: Text('已完成')),
            ],
          ),
        ],
      ),
    );
  }
}
