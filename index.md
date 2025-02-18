---
title: Online Hosted Instructions
permalink: index.html
layout: home
---

This repository contains the hands-on lab exercises for Microsoft course [DP-420 Designing and Implementing Cloud-Native Applications Using Microsoft Azure Cosmos DB][course-description] and the equivalent [self-paced modules on Microsoft Learn][learn-collection]. The exercises are designed to accompany the learning materials and enable you to practice using the technologies they describe.

> &#128221; To complete these exercises, you’ll require a Microsoft Azure subscription. You can sign up for a free trial at [https://azure.microsoft.com][azure].

# Labs

## C# labs

{% assign labs = site.pages | where_exp:"page", "page.url contains '/instructions'" %}
{% assign csharp_setup_labs = "" | split: "," %}
{% assign csharp_regular_labs = "" | split: "," %}
{% assign genai_setup_labs = "" | split: "," %}
{% assign genai_python_labs = "" | split: "," %}
{% assign genai_javascript_labs = "" | split: "," %}

{% for activity in labs %}
  {% assign segments = activity.url | split: "/" %}

  {% if segments[1] == "instructions" and segments.size == 3 %}
    {% if activity.lab.module contains "Setup" %}
      {% assign csharp_setup_labs = csharp_setup_labs | push: activity %}
    {% else %}
      {% assign csharp_regular_labs = csharp_regular_labs | push: activity %}
    {% endif %}
  
  {% elsif activity.url contains '/gen-ai/python/instructions' %}
    {% assign genai_python_labs = genai_python_labs | push: activity %}
  
  {% elsif activity.url contains '/gen-ai/javascript/instructions' %}
    {% assign genai_javascript_labs = genai_javascript_labs | push: activity %}
  
  {% elsif activity.url contains '/gen-ai/common/instructions' and activity.lab.module contains "Setup" %}
    {% assign genai_setup_labs = genai_setup_labs | push: activity %}
  {% endif %}
{% endfor %}

---

### **Setup labs**

| Module | Lab |
| --- | --- |
{% for activity in csharp_setup_labs %}| {{ activity.lab.module }} | [{{ activity.lab.title }}]({{ site.github.url }}{{ activity.url }}) |  
{% endfor %}

---

### **Labs**

| Module | Lab |
| --- | --- |
{% for activity in csharp_regular_labs %}| {{ activity.lab.module }} | [{{ activity.lab.title }}]({{ site.github.url }}{{ activity.url }}) |  
{% endfor %}

---

## **Generative AI labs**

### **Common setup labs**

| Module | Lab |
| --- | --- |
{% for activity in genai_setup_labs %}| {{ activity.lab.module }} | [{{ activity.lab.title }}]({{ site.github.url }}{{ activity.url }}) |  
{% endfor %}

---

### **JavaScript labs**

| Module | Lab |
| --- | --- |
{% for activity in genai_javascript_labs %}| {{ activity.lab.module }} | [{{ activity.lab.title }}]({{ site.github.url }}{{ activity.url }}) |  
{% endfor %}

---

### **Python labs**

| Module | Lab |
| --- | --- |
{% for activity in genai_python_labs %}| {{ activity.lab.module }} | [{{ activity.lab.title }}]({{ site.github.url }}{{ activity.url }}) |  
{% endfor %}

[azure]: https://azure.microsoft.com
[course-description]: https://docs.microsoft.com/learn/certifications/courses/dp-420t00
[learn-collection]: https://docs.microsoft.com/users/msftofficialcurriculum-4292/collections/1k8wcz8zooj2nx
