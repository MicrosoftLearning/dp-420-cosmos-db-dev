---
title: Online Hosted Instructions
permalink: index.html
layout: home
---

This repository contains the hands-on lab exercises for Microsoft course [DP-420 Designing and Implementing a Microsoft Azure AI Solution][course-description] and the equivalent [self-paced modules on Microsoft Learn][learn-collection]. The exercises are designed to accompany the learning materials and enable you to practice using the technologies they describe.

> &#128221; To complete these exercises, you’ll require a Microsoft Azure subscription. You can sign up for a free trial at [https://azure.microsoft.com][azure].

## Labs

{% assign labs = site.pages | where_exp:"page", "page.url contains '/instructions'" %}
| Module | Lab |
| --- | --- |
{% for activity in labs  %}| {{ activity.lab.module }} | [{{ activity.lab.title }}]({{ site.github.url }}{{ activity.url }}) |
{% endfor %}

[azure]: https://azure.microsoft.com
[course-description]: https://docs.microsoft.com/learn/certifications/courses/dp-420t00
[learn-collection]: https://docs.microsoft.com/users/msftofficialcurriculum-4292/collections/1k8wcz8zooj2nx
