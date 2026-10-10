import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'captura_calificaciones_screen.dart' show guardianUrl;

class PedagogiaPaseListaScreen extends StatefulWidget {
  final String programa,generacion,grupo,materia;
  const PedagogiaPaseListaScreen({super.key,required this.programa,required this.generacion,required this.grupo,required this.materia});
  @override State<PedagogiaPaseListaScreen> createState()=>_PedagogiaPaseListaScreenState();
}
class _PedagogiaPaseListaScreenState extends State<PedagogiaPaseListaScreen> {
  bool busy=false; String? error; List<Map<String,dynamic>> alumnos=[];
  DateTime fecha=DateTime.now(); bool guardado=false;
  String get dia=>'${fecha.year.toString().padLeft(4,'0')}-${fecha.month.toString().padLeft(2,'0')}-${fecha.day.toString().padLeft(2,'0')}';
  Map<String,dynamic> get args=>{'programa':widget.programa,'generacion':widget.generacion,'grupo':widget.grupo,'materia':widget.materia,'fecha':dia};
  @override void initState(){super.initState();cargar();}
  Future<void> cargar() async {setState((){busy=true;error=null;});try{
    final r=await http.get(Uri.parse(guardianUrl).replace(queryParameters:{'accion':'pedagogia_asistencia',...args})).timeout(const Duration(seconds:45));
    final v=jsonDecode(r.body) as Map<String,dynamic>;if(v['ok']!=true)throw Exception(v['error']);
    if(mounted)setState((){alumnos=(v['alumnos'] as List).map((e)=>Map<String,dynamic>.from(e as Map)).toList();guardado=v['guardado']==true;});
  }catch(e){if(mounted)setState(()=>error='$e');}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> guardar()async{setState(()=>busy=true);try{
    final r=await http.post(Uri.parse(guardianUrl),headers:{'Content-Type':'text/plain;charset=utf-8'},body:jsonEncode({'accion':'pedagogia_asistencia_guardar',...args,'alumnos':alumnos.map((a)=>{'matricula':a['matricula'],'estado':a['estado']}).toList()})).timeout(const Duration(seconds:60));
    final v=jsonDecode(r.body) as Map<String,dynamic>;if(v['ok']!=true)throw Exception(v['error']);
    if(mounted){setState(()=>guardado=true);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Asistencia guardada')));}
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se guardó: $e')));}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Pase de lista presencial')),body:busy?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Text(error!)):Column(children:[
    ListTile(title:Text(widget.materia),subtitle:Text('${widget.generacion} · ${widget.grupo}${guardado?' · Guardado':''}'),trailing:IconButton(icon:const Icon(Icons.calendar_today),onPressed:()async{final f=await showDatePicker(context:context,initialDate:fecha,firstDate:DateTime(2025),lastDate:DateTime.now());if(f!=null){fecha=f;await cargar();}})),
    Expanded(child:ListView.builder(itemCount:alumnos.length,itemBuilder:(context,i){final a=alumnos[i];return ListTile(title:Text('${a['nombre']}'),subtitle:Text('${a['matricula']}'),trailing:DropdownButton<String>(value:('${a['estado']}'.isEmpty ? null : '${a['estado']}'),hint:const Text('Marcar'),items:const [DropdownMenuItem(value:'P',child:Text('Presente')),DropdownMenuItem(value:'F',child:Text('Falta')),DropdownMenuItem(value:'J',child:Text('Justificada'))],onChanged:(v)=>setState(()=>a['estado']=v)));})),
    Padding(padding:const EdgeInsets.all(16),child:SizedBox(width:double.infinity,child:FilledButton(onPressed:alumnos.isEmpty || alumnos.any((a)=>!['P','F','J'].contains(a['estado']))?null:guardar,child:const Text('Guardar pase de lista'))))
  ]));
}
