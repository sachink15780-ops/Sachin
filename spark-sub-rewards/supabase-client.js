import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "./supabase-config.js";
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

export async function signUp(email,password,displayName){
  const {data,error}=await supabase.auth.signUp({email,password,options:{data:{display_name:displayName}}});
  if(error) throw error; return data;
}
export async function signIn(email,password){
  const {data,error}=await supabase.auth.signInWithPassword({email,password});
  if(error) throw error; return data;
}
export async function signOut(){ const {error}=await supabase.auth.signOut(); if(error)throw error; }
export async function getProfile(){
  const {data:{user}}=await supabase.auth.getUser(); if(!user) return null;
  const {data,error}=await supabase.from("profiles").select("*").eq("id",user.id).single();
  if(error)throw error; return data;
}
export async function getTasks(){
  const {data,error}=await supabase.from("tasks").select("*").eq("is_active",true).order("created_at",{ascending:false});
  if(error)throw error; return data||[];
}
export async function submitProof(taskId,file){
  const {data:{user}}=await supabase.auth.getUser(); if(!user) throw new Error("Please log in first.");
  const ext=(file.name.split(".").pop()||"jpg").replace(/[^a-z0-9]/gi,"").toLowerCase();
  const path=user.id+"/"+crypto.randomUUID()+"."+ext;
  const up=await supabase.storage.from("task-proofs").upload(path,file,{upsert:false});
  if(up.error)throw up.error;
  const ins=await supabase.from("submissions").insert({user_id:user.id,task_id:taskId,proof_image_path:path,status:"pending"});
  if(ins.error){await supabase.storage.from("task-proofs").remove([path]);throw ins.error;}
  return ins.data;
}
export async function requestWithdrawal(amount,upi){
  const {data:{user}}=await supabase.auth.getUser(); if(!user)throw new Error("Please log in first.");
  const {data,error}=await supabase.rpc("request_withdrawal",{p_amount:amount,p_upi_id:upi});
  if(error)throw error; return data;
}
export async function myWallet(){
  const {data:{user}}=await supabase.auth.getUser(); if(!user)throw new Error("Please log in first.");
  const {data,error}=await supabase.from("wallets").select("balance").eq("user_id",user.id).single();
  if(error)throw error; return data;
}
